<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\RequestActivityEvent;
use App\Models\VitalReportRequest;
use App\Services\VitalReportIssuer;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The care team's side of a patient's vital report request.
 *
 * Every clinician on the patient's caseload sees every request — that is
 * deliberate, and it is what makes cover possible when one of them is away.
 * What was missing was ownership: two doctors could open the same request and
 * both write the report, and a request nobody had started looked identical to
 * one being worked on right now.
 *
 * So the queue is shared and the work is not. A request must be claimed before
 * it can be finished, exactly one clinician can hold it, and every claim,
 * release and resolution is written to the request's own trail — which the
 * patient reads too.
 */
class DoctorVitalReportRequestsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $patientIds = DoctorAccess::caseloadPatientIds($request->user());

        $requests = VitalReportRequest::with(['events', 'user'])
            ->whereIn('user_id', $patientIds)
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
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);

        if (! $vitalReportRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $vitalReportRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        $label = 'Dr. '.$request->user()->fullName();

        if (! $vitalReportRequest->claimFor($request->user(), $label)) {
            $holder = $vitalReportRequest->fresh();

            return $this->error(
                ($holder->claimed_by_name ?? 'Another clinician').' is already working on this request.',
                409,
                ['request' => $holder->load('events')->toStaffArray($request->user())],
            );
        }

        DoctorAccess::audit(
            $request->user(),
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
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);

        if (! $vitalReportRequest->isClaimedBy($request->user())) {
            return $this->error('You are not the one working on this request.', 403);
        }

        $data = $request->validate(['note' => 'nullable|string|max:280']);

        $vitalReportRequest->release(
            $request->user(),
            'Dr. '.$request->user()->fullName(),
            $data['note'] ?? null,
        );

        DoctorAccess::audit(
            $request->user(),
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
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);

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

        $label = 'Dr. '.$request->user()->fullName();

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

        DoctorAccess::audit(
            $request->user(),
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
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);

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
            'Dr. '.$request->user()->fullName(),
            $request->user()->id,
            $data['note'] ?? null,
        );

        DoctorAccess::audit(
            $request->user(),
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
    ): void {
        try {
            AppNotification::create([
                'user_id' => $req->user_id,
                'kind' => 'report',
                'title' => $title,
                'body' => $body,
                'action_route' => $route,
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
