<?php

namespace App\Http\Controllers\Concerns;

use App\Models\AppNotification;
use App\Models\MedicalDocument;
use App\Models\RequestActivityEvent;
use App\Models\VitalReportRequest;
use App\Services\VitalReportIssuer;
use Illuminate\Http\Request;

/**
 * The care team's side of a patient's vital report request, written once.
 *
 * The queue escalates on its own — doctor for 48 hours, then mCare assistant,
 * then admin — but only doctors could ever act on it. A request that aged past
 * its first window was handed to a tier with no claim route, no fulfil route
 * and no screen: it moved to somebody who could not touch it, and the patient
 * waited on a report nobody was able to produce. The escalation was real and
 * the destination was a dead end.
 *
 * Everything about how the queue behaves lives here, so a request means the
 * same thing whichever tier is holding it. The host controller supplies only
 * what genuinely differs: who may act on a given patient, what the patient
 * reads as the actor's name, and where the act is audited.
 */
trait ManagesVitalReportQueue
{
    /** Refuse the caller unless they may work this patient's request. */
    abstract protected function assertQueueAccess(Request $request, VitalReportRequest $vitalReportRequest): void;

    /**
     * The patients whose requests this caller sees, or null for all of them.
     *
     * A doctor sees their caseload. Admin staff are not on a caseload — which
     * is the whole reason the queue escalates to them — so they see the queue
     * entire.
     *
     * @return list<int>|null
     */
    abstract protected function queueScopedPatientIds(Request $request): ?array;

    /** What the patient reads as "who is preparing my report". */
    abstract protected function queueActorLabel(Request $request): string;

    abstract protected function recordQueueAudit(Request $request, string $action, string $detail): void;

    public function index(Request $request)
    {
        $patientIds = $this->queueScopedPatientIds($request);

        $requests = VitalReportRequest::with(['events', 'user'])
            // Null means no caseload to narrow by, which is the admin tiers:
            // they are exactly who an escalated request lands on, so scoping
            // them to a caseload they do not have would show them nothing.
            ->when($patientIds !== null, fn ($q) => $q->whereIn('user_id', $patientIds))
            // Open work first, and within that the longest-waiting first: a
            // queue sorted purely by recency buries the request that has been
            // ignored the longest.
            ->orderByRaw("CASE WHEN status IN ('pending','in_progress') THEN 0 ELSE 1 END")
            ->orderByDesc('created_at')
            ->get();

        return $this->success([
            'requests' => $requests
                ->map(fn (VitalReportRequest $r) => $r->toStaffArray($request->user()))
                ->all(),
        ]);
    }

    /**
     * Take the request on.
     *
     * Losing the race is a normal outcome, not an error in the caller: two
     * clinicians opening the inbox at the same moment is exactly the situation
     * this exists for. The loser is told who holds it and sent the fresh row
     * so their list stops offering them a button that cannot work.
     */
    public function claim(Request $request, VitalReportRequest $vitalReportRequest)
    {
        $this->assertQueueAccess($request, $vitalReportRequest);

        if (! $vitalReportRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $vitalReportRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        $label = $this->queueActorLabel($request);

        if (! $vitalReportRequest->claimFor($request->user(), $label)) {
            $holder = $vitalReportRequest->fresh();

            return $this->error(
                ($holder->claimed_by_name ?? 'Another clinician').' is already working on this request.',
                409,
                ['request' => $holder->load('events')->toStaffArray($request->user())],
            );
        }

        $this->recordQueueAudit(
            $request,
            'Claimed vital report request',
            "Request #{$vitalReportRequest->id}",
        );

        $this->tellPatient(
            $vitalReportRequest,
            'Your vital report is being prepared',
            $label.' has taken on your report request.',
        );

        return $this->success(
            ['request' => $vitalReportRequest->fresh()->load('events')->toStaffArray($request->user())],
            'You are now working on this request.',
        );
    }

    /**
     * Hand it back to the queue.
     *
     * A clinician who picks up a request they cannot finish — wrong specialty,
     * going off shift — must be able to put it down again without resolving it
     * falsely. Only the holder can, so releasing cannot be used to take work
     * off a colleague.
     */
    public function release(Request $request, VitalReportRequest $vitalReportRequest)
    {
        $this->assertQueueAccess($request, $vitalReportRequest);

        if (! $vitalReportRequest->isClaimedBy($request->user())) {
            return $this->error('You are not the one working on this request.', 403);
        }

        $data = $request->validate(['note' => 'nullable|string|max:280']);

        $vitalReportRequest->release(
            $request->user(),
            $this->queueActorLabel($request),
            $data['note'] ?? null,
        );

        $this->recordQueueAudit(
            $request,
            'Released vital report request',
            "Request #{$vitalReportRequest->id}",
        );

        return $this->success(
            ['request' => $vitalReportRequest->fresh()->load('events')->toStaffArray($request->user())],
            'Request returned to the care team queue.',
        );
    }

    /**
     * Finish it: render the report, file it in the patient's documents, close
     * the request.
     *
     * Claiming is a precondition rather than something done implicitly here.
     * An unclaimed request being resolved out of nowhere is the duplicate-work
     * problem in a different shape — the colleague who was mid-way through
     * writing the same report gets no warning at all. A clinician who has not
     * claimed it is told to, which costs them one tap.
     */
    public function fulfill(Request $request, VitalReportRequest $vitalReportRequest, VitalReportIssuer $issuer)
    {
        $this->assertQueueAccess($request, $vitalReportRequest);

        $data = $request->validate([
            'note' => 'nullable|string|max:1000',
        ]);

        if (! $vitalReportRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $vitalReportRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        if ($vitalReportRequest->isClaimed() && ! $vitalReportRequest->isClaimedBy($request->user())) {
            return $this->error(
                $vitalReportRequest->claimed_by_name.' is working on this request. '
                .'Ask them to hand it back before completing it.',
                409,
                ['request' => $vitalReportRequest->load('events')->toStaffArray($request->user())],
            );
        }

        $label = $this->queueActorLabel($request);

        if (! $vitalReportRequest->isClaimed()
            && ! $vitalReportRequest->claimFor($request->user(), $label)) {
            $holder = $vitalReportRequest->fresh();

            return $this->error(
                ($holder->claimed_by_name ?? 'Another clinician').' just took this request on.',
                409,
                ['request' => $holder->load('events')->toStaffArray($request->user())],
            );
        }

        // Fulfilling *is* signing: the clinician is attesting to findings the
        // patient will be handed. Recorded on the request before the document
        // is rendered, so the signature block the patient reads and the record
        // the practice keeps are the same fact rather than two.
        $signedAt = now();

        $vitalReportRequest->forceFill([
            'signed_by_user_id' => $request->user()->id,
            'signed_by' => $label,
            'signed_by_role' => $request->user()->role,
            'signed_at' => $signedAt,
        ])->save();

        $document = $issuer->issue(
            $vitalReportRequest,
            $request->user(),
            $label,
            $data['note'] ?? null,
        );

        $vitalReportRequest->update([
            'status' => VitalReportRequest::FULFILLED,
            'responded_at' => $signedAt,
            'responded_by' => $label,
            'response_note' => $data['note'] ?? null,
            'resolved_at' => $signedAt,
            'document_id' => $document?->id,
        ]);

        RequestActivityEvent::record(
            $vitalReportRequest,
            RequestActivityEvent::RESOLVED,
            $label,
            $request->user()->id,
            $data['note'] ?? null,
        );

        $this->recordQueueAudit(
            $request,
            'Fulfilled vital report request',
            "Request #{$vitalReportRequest->id}",
        );

        // The document is the point, so the alert routes to it rather than
        // back to the vitals screen the request was raised from.
        $this->tellPatient(
            $vitalReportRequest,
            'Your vital report is signed and ready',
            $document
                ? $label.' signed your report. It is filed under Documents → Vital report.'
                : $label.' completed your requested report.',
            $document ? '/patient/documents' : '/patient/vitals',
            $document,
        );

        return $this->success(
            ['request' => $vitalReportRequest->fresh()->load('events')->toStaffArray($request->user())],
            $document
                ? 'Report issued and filed in the patient\'s documents.'
                : 'Request completed, but the report file could not be generated.',
        );
    }

    public function escalate(Request $request, VitalReportRequest $vitalReportRequest)
    {
        $this->assertQueueAccess($request, $vitalReportRequest);

        $data = $request->validate(['note' => 'nullable|string|max:280']);

        // Escalating is handing the request away, so it cannot stay claimed by
        // the person handing it over — otherwise the tier it lands on sees a
        // request that looks like someone else's work in progress.
        $vitalReportRequest->update([
            'current_responder' => 'admin',
            'last_escalated_at' => now(),
            'claimed_by' => null,
            'claimed_by_name' => null,
            'claimed_at' => null,
            'status' => VitalReportRequest::PENDING,
        ]);

        RequestActivityEvent::record(
            $vitalReportRequest,
            RequestActivityEvent::ESCALATED,
            $this->queueActorLabel($request),
            $request->user()->id,
            $data['note'] ?? null,
        );

        $this->recordQueueAudit(
            $request,
            'Escalated vital report request',
            "Request #{$vitalReportRequest->id}",
        );

        return $this->success(
            ['request' => $vitalReportRequest->fresh()->load('events')->toStaffArray($request->user())],
            'Request escalated to care admin.',
        );
    }

    private function tellPatient(
        VitalReportRequest $req,
        string $title,
        string $body,
        string $route = '/patient/vitals',
        ?MedicalDocument $document = null,
    ): void {
        try {
            AppNotification::create([
                'user_id' => $req->user_id,
                'kind' => 'report',
                'title' => $title,
                'body' => $body,
                'action_route' => $route,
                // Names the filed report, so "your vital report is ready"
                // opens the report rather than the documents list.
                'action_arguments' => array_filter([
                    'document_id' => $document?->id === null
                        ? null
                        : (string) $document->id,
                ]),
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
