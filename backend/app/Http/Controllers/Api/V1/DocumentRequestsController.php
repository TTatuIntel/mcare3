<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\DocumentRequest;
use App\Models\RequestActivityEvent;
use App\Support\ApiResponse;
use App\Support\DocumentCategories;
use Illuminate\Http\Request;

/**
 * The patient asking their care team for a document.
 *
 * Documents only ever moved one way: patients uploaded, clinicians filed, and
 * a patient who needed a referral letter or a copy of a discharge summary rang
 * the desk and hoped. Nothing about the ask existed in the record, so nobody
 * could see it was outstanding and nobody could be shown to have answered it.
 *
 * A request is addressed either to the whole care team or to one named doctor.
 * Both are visible to the whole team — naming a doctor says who it is waiting
 * on, not who is allowed to answer, because a request stuck behind one
 * clinician's annual leave is the failure mode this is meant to prevent.
 */
class DocumentRequestsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $requests = DocumentRequest::with(['events', 'targetDoctor'])
            ->where('user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->get();

        return $this->success([
            'requests' => $requests->map->toApiArray()->all(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'title' => 'required|string|max:160',
            'category' => 'required|string|in:'.DocumentCategories::rule(),
            'note' => 'nullable|string|max:1000',
            'target' => 'required|string|in:team,doctor',
            'target_doctor_id' => 'nullable|exists:users,id',
            'needed_by' => 'nullable|date|after_or_equal:today',
        ]);

        $doctorId = $data['target'] === DocumentRequest::TARGET_DOCTOR
            ? ($data['target_doctor_id'] ?? null)
            : null;

        if ($data['target'] === DocumentRequest::TARGET_DOCTOR) {
            if ($doctorId === null) {
                return $this->error('Choose which doctor you are asking.', 422);
            }
            // Asking a doctor who is not on your team is not a request, it is
            // a message they will never see — refuse it here rather than let
            // it sit unanswered in a queue nobody reads.
            if (! in_array((int) $doctorId, $this->careTeamUserIds($request->user()->id), true)) {
                return $this->error(
                    'That doctor is not on your care team. Ask the team instead, '
                    .'or request them as a provider first.',
                    422,
                );
            }
        }

        $req = DocumentRequest::create([
            'user_id' => $request->user()->id,
            'title' => trim($data['title']),
            'category' => $data['category'],
            'note' => $data['note'] ?? null,
            'target' => $data['target'],
            'target_doctor_id' => $doctorId,
            'needed_by' => $data['needed_by'] ?? null,
            'status' => DocumentRequest::PENDING,
        ]);

        RequestActivityEvent::record(
            $req,
            RequestActivityEvent::OPENED,
            $request->user()->fullName(),
            $request->user()->id,
            $data['note'] ?? null,
        );

        $this->notifyCareTeam($req, $request->user()->fullName());

        return $this->success(
            ['request' => $req->fresh()->load(['events', 'targetDoctor'])->toApiArray()],
            $doctorId
                ? 'Request sent. Your care team can see it too.'
                : 'Request sent to your care team.',
            201,
        );
    }

    public function cancel(Request $request, DocumentRequest $documentRequest)
    {
        abort_unless($documentRequest->user_id === $request->user()->id, 403);

        if (! $documentRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422);
        }

        $documentRequest->update([
            'status' => DocumentRequest::CANCELLED,
            'claimed_by' => null,
            'claimed_by_name' => null,
            'claimed_at' => null,
            'resolved_at' => now(),
        ]);

        RequestActivityEvent::record(
            $documentRequest,
            RequestActivityEvent::CANCELLED,
            $request->user()->fullName(),
            $request->user()->id,
        );

        return $this->success(
            ['request' => $documentRequest->fresh()->load(['events', 'targetDoctor'])->toApiArray()],
            'Request cancelled.',
        );
    }

    /** The user ids of the doctors currently assigned to this patient. */
    private function careTeamUserIds(int $patientUserId): array
    {
        return CareProvider::whereIn(
            'id',
            CareAssignment::where('patient_user_id', $patientUserId)
                ->whereNull('ended_at')
                ->pluck('provider_id'),
        )
            ->pluck('user_id')
            ->filter()
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Alerts the team. A request naming one doctor still reaches everyone —
     * the name is who it is waiting on, not a private channel — but only the
     * named doctor is told it is theirs.
     */
    private function notifyCareTeam(DocumentRequest $req, string $patientName): void
    {
        try {
            foreach ($this->careTeamUserIds($req->user_id) as $doctorUserId) {
                $mine = (int) $req->target_doctor_id === $doctorUserId;

                AppNotification::create([
                    'user_id' => $doctorUserId,
                    'kind' => 'document',
                    'title' => $mine
                        ? 'Document requested from you'
                        : 'Document requested from the care team',
                    'body' => $patientName.' asked for "'.$req->title.'" ('
                        .DocumentCategories::label($req->category).').',
                    'action_route' => '/doctor/inbox',
                    'read' => false,
                ]);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
