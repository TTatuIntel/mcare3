<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Admin / assistant triage of patient → provider care requests.
 *
 * Approving a request is what creates the matching care_assignment, so this
 * controller is the single write path behind the merged "Care requests &
 * assignments" admin screen:
 *
 *   • approve as requested   → assign the doctor the patient asked for
 *   • approve + re-route     → assign a more suitable doctor, reason required
 *   • decline                → reason required, no assignment created
 */
class CareRequestsController extends Controller
{
    use ApiResponse;

    /** Relationship types an assignment may carry. */
    private const ROLES = ['Primary', 'Consulting', 'Specialist'];

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $query = CareRequest::query()
            ->with(['user', 'provider', 'assignedProvider', 'decider'])
            ->orderByDesc('created_at');

        if ($status = $request->query('status')) {
            // The client speaks "rejected"; the column has always stored
            // "cancelled" for the same state.
            $query->when(
                $status === 'rejected',
                fn ($q) => $q->whereIn('status', ['rejected', 'cancelled']),
                fn ($q) => $q->where('status', $status),
            );
        }
        if ($patientId = $request->query('patient_id')) {
            $query->where('user_id', $patientId);
        }
        if ($providerId = $request->query('provider_id')) {
            $query->where(function ($q) use ($providerId) {
                $q->where('provider_id', $providerId)
                    ->orWhere('assigned_provider_id', $providerId);
            });
        }
        if ($term = trim((string) $request->query('query', ''))) {
            $query->where(function ($q) use ($term) {
                $q->where('provider_name', 'like', "%{$term}%")
                    ->orWhere('reason', 'like', "%{$term}%")
                    ->orWhereHas('user', function ($u) use ($term) {
                        $u->where('first_name', 'like', "%{$term}%")
                            ->orWhere('last_name', 'like', "%{$term}%");
                    });
            });
        }

        $requests = $query->limit(200)->get()->map(function (CareRequest $r) {
            $arr = $r->toApiArray();
            // Legacy key kept for older clients that read patient_user_id.
            $arr['patient_user_id'] = (string) $r->user_id;
            $arr['patient_name'] = $r->user?->fullName();

            return $arr;
        });

        return $this->success(['care_requests' => $requests]);
    }

    /**
     * Approve a pending request and create the care assignment.
     *
     * When the resolved provider differs from the one the patient requested,
     * a note explaining the re-route is mandatory — that reason is what the
     * patient sees in their notification.
     */
    public function route(Request $request, CareRequest $careRequest)
    {
        $data = $request->validate([
            'provider_id' => 'nullable|exists:care_providers,id',
            'provider_user_id' => 'nullable|exists:users,id',
            'role' => 'nullable|string|in:'.implode(',', self::ROLES),
            'note' => 'nullable|string|max:280',
        ]);

        if ($careRequest->status !== 'pending') {
            return $this->error('Request is not pending.', 422);
        }

        $providerId = $data['provider_id'] ?? null;
        if ($providerId === null && ! empty($data['provider_user_id'])) {
            $providerId = CareProvider::resolveForUser($data['provider_user_id'])->id;
        }
        $providerId ??= $careRequest->provider_id;

        if ($providerId === null) {
            return $this->error('No provider to assign.', 422);
        }

        $note = trim((string) ($data['note'] ?? '')) ?: null;
        $role = $data['role'] ?? 'Primary';
        $reassigned = (int) $providerId !== (int) $careRequest->provider_id;

        if ($reassigned && $note === null) {
            return $this->error(
                'A reason is required when assigning a provider other than the one requested.',
                422,
            );
        }

        $actor = $request->user();
        $provider = CareProvider::find($providerId);
        $providerLabel = $provider?->name ?? 'your care provider';

        DB::transaction(function () use (
            $careRequest, $providerId, $role, $note, $reassigned, $actor, $providerLabel
        ) {
            $careRequest->update([
                'status' => 'approved',
                'assigned_provider_id' => $providerId,
                'assignment_role' => $role,
                'decision_note' => $note,
                'decided_by' => $actor?->id,
                'decided_at' => now(),
            ]);

            $existing = CareAssignment::query()
                ->where('patient_user_id', $careRequest->user_id)
                ->where('provider_id', $providerId)
                ->whereNull('ended_at')
                ->first();

            if ($existing) {
                // Already paired — honour the relationship type chosen now and
                // keep the reason behind this approval on the row.
                $existing->update([
                    'role' => $role,
                    'assigned_reason' => $note ?? $existing->assigned_reason,
                    'assigned_by' => $actor?->id,
                ]);
            } else {
                CareAssignment::create([
                    'patient_user_id' => $careRequest->user_id,
                    'provider_id' => $providerId,
                    'role' => $role,
                    'assigned_at' => now(),
                    'assigned_reason' => $note,
                    'assigned_by' => $actor?->id,
                ]);
            }

            $body = $reassigned
                ? "You've been assigned to {$providerLabel}. {$note}"
                : "You're now assigned to {$providerLabel}."
                    .($note === null ? '' : " {$note}");

            AppNotification::create([
                'user_id' => $careRequest->user_id,
                'kind' => 'careRequest',
                'title' => $reassigned
                    ? 'Care request approved — provider updated'
                    : 'Care request approved',
                'body' => $body,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        $this->audit->record(
            $actor,
            $reassigned ? 'care_request.reassigned' : 'care_request.routed',
            ($careRequest->user?->fullName() ?? 'Patient').' → '.$providerLabel,
            'activity',
            [
                'care_request_id' => $careRequest->id,
                'provider_id' => $providerId,
                'requested_provider_id' => $careRequest->provider_id,
                'role' => $role,
                'reason' => $note,
            ],
        );

        $fresh = $careRequest->fresh(['user', 'provider', 'assignedProvider', 'decider']);
        $payload = $fresh->toApiArray();
        $payload['patient_user_id'] = (string) $fresh->user_id;
        $payload['patient_name'] = $fresh->user?->fullName();

        return $this->success(
            ['care_request' => $payload],
            $reassigned ? 'Assigned to a different provider.' : 'Routed.',
        );
    }

    /** Decline a pending request. The reason is shown to the patient. */
    public function cancel(Request $request, CareRequest $careRequest)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($careRequest->status !== 'pending') {
            return $this->error('Request is not pending.', 422);
        }

        $actor = $request->user();

        $careRequest->update([
            'status' => 'cancelled',
            'decision_note' => $data['reason'],
            'decided_by' => $actor?->id,
            'decided_at' => now(),
        ]);

        AppNotification::create([
            'user_id' => $careRequest->user_id,
            'kind' => 'careRequest',
            'title' => 'Care request declined',
            'body' => $data['reason'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $actor,
            'care_request.cancelled',
            $careRequest->user?->fullName() ?? 'Patient',
            'activity',
            ['care_request_id' => $careRequest->id, 'reason' => $data['reason']],
        );

        $fresh = $careRequest->fresh(['user', 'provider', 'assignedProvider', 'decider']);
        $payload = $fresh->toApiArray();
        $payload['patient_user_id'] = (string) $fresh->user_id;
        $payload['patient_name'] = $fresh->user?->fullName();

        return $this->success(['care_request' => $payload], 'Declined.');
    }
}
