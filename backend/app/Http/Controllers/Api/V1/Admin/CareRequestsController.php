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
 * Routing creates the matching care_assignment.
 */
class CareRequestsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $status = $request->query('status');
        $query = CareRequest::query()
            ->with(['user', 'provider'])
            ->orderByDesc('created_at');

        if ($status) {
            $query->where('status', $status);
        }

        $requests = $query->limit(200)->get()->map(function (CareRequest $r) {
            $arr = $r->toApiArray();
            $arr['patient_user_id'] = (string) $r->user_id;
            $arr['patient_name'] = $r->user?->fullName();
            return $arr;
        });

        return $this->success(['care_requests' => $requests]);
    }

    public function route(Request $request, CareRequest $careRequest)
    {
        $data = $request->validate([
            'provider_id' => 'nullable|exists:care_providers,id',
        ]);

        if ($careRequest->status !== 'pending') {
            return $this->error('Request is not pending.', 422);
        }

        $providerId = $data['provider_id'] ?? $careRequest->provider_id;

        DB::transaction(function () use ($careRequest, $providerId) {
            $careRequest->update([
                'status' => 'approved',
                'provider_id' => $providerId,
            ]);

            $existing = CareAssignment::query()
                ->where('patient_user_id', $careRequest->user_id)
                ->where('provider_id', $providerId)
                ->whereNull('ended_at')
                ->first();
            if (! $existing) {
                CareAssignment::create([
                    'patient_user_id' => $careRequest->user_id,
                    'provider_id' => $providerId,
                    'role' => 'Primary',
                    'assigned_at' => now(),
                ]);
            }

            AppNotification::create([
                'user_id' => $careRequest->user_id,
                'kind' => 'careRequest',
                'title' => 'Care request approved',
                'body' => 'You\'re now assigned to '.$careRequest->provider_name.'.',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        $provider = CareProvider::find($providerId);
        $this->audit->record(
            $request->user(),
            'care_request.routed',
            ($careRequest->user?->fullName() ?? 'Patient').' → '.($provider?->name ?? 'Provider'),
            'activity',
            ['care_request_id' => $careRequest->id, 'provider_id' => $providerId],
        );

        return $this->success(['care_request' => $careRequest->fresh()->toApiArray()], 'Routed.');
    }

    public function cancel(Request $request, CareRequest $careRequest)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($careRequest->status !== 'pending') {
            return $this->error('Request is not pending.', 422);
        }

        $careRequest->update(['status' => 'cancelled']);

        AppNotification::create([
            'user_id' => $careRequest->user_id,
            'kind' => 'careRequest',
            'title' => 'Care request cancelled',
            'body' => $data['reason'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request->user(),
            'care_request.cancelled',
            $careRequest->user?->fullName() ?? 'Patient',
            'activity',
            ['care_request_id' => $careRequest->id, 'reason' => $data['reason']],
        );

        return $this->success(['care_request' => $careRequest->fresh()->toApiArray()], 'Cancelled.');
    }
}
