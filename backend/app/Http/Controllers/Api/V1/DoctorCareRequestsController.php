<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * RETIRED — no route points here.
 *
 * Care-request triage is an admin / mCare-assistant responsibility. A doctor
 * sees the care team they were assigned to and never makes the accept or
 * decline decision, so `doctor/care-requests/{id}/accept|decline` were removed
 * from routes/api.php. DoctorCareRequestDecisionTest pins that they stay gone.
 *
 * The class is kept only so the work in it is not lost; do not wire it back
 * up. If nothing here is worth salvaging, delete the file.
 */
class DoctorCareRequestsController extends Controller
{
    use ApiResponse;

    public function accept(Request $request, CareRequest $careRequest)
    {
        $provider = $this->myProvider($request);
        abort_unless($careRequest->provider_id === $provider->id, 403, 'Not your request.');

        $careRequest->update([
            'status' => 'accepted',
            'assigned_provider_id' => $provider->id,
            'assignment_role' => 'Primary',
            'decided_by' => $request->user()->id,
            'decided_at' => now(),
        ]);
        // Doctors may accept a request the admin already routed to them.
        CareAssignment::firstOrCreate(
            [
                'patient_user_id' => $careRequest->user_id,
                'provider_id' => $provider->id,
                'ended_at' => null,
            ],
            [
                'role' => 'Primary',
                'assigned_at' => now(),
                'assigned_by' => $request->user()->id,
            ],
        );
        AppNotification::create([
            'user_id' => $careRequest->user_id,
            'kind' => 'careRequest',
            'title' => 'Your provider request was accepted',
            'body' => 'Dr. '.$request->user()->fullName().' is now part of your care team.',
            'action_route' => '/patient/care-team',
            'read' => false,
        ]);
        DoctorAccess::audit(
            $request->user(),
            'Accepted care request',
            "Patient #{$careRequest->user_id}"
        );
        return $this->success(['request' => $careRequest->fresh()->toApiArray()], 'Request accepted.');
    }

    public function decline(Request $request, CareRequest $careRequest)
    {
        $provider = $this->myProvider($request);
        abort_unless($careRequest->provider_id === $provider->id, 403, 'Not your request.');

        $data = $request->validate(['reason' => 'nullable|string|max:200']);
        $careRequest->update([
            'status' => 'declined',
            'decision_note' => $data['reason'] ?? null,
            'decided_by' => $request->user()->id,
            'decided_at' => now(),
        ]);
        AppNotification::create([
            'user_id' => $careRequest->user_id,
            'kind' => 'careRequest',
            'title' => 'Provider request declined',
            'body' => 'Dr. '.$request->user()->fullName().' is unable to take on new patients at this time.',
            'action_route' => '/patient/care-team',
            'read' => false,
        ]);
        DoctorAccess::audit(
            $request->user(),
            'Declined care request',
            "Patient #{$careRequest->user_id}".(! empty($data['reason']) ? " — {$data['reason']}" : '')
        );
        return $this->success(['request' => $careRequest->fresh()->toApiArray()], 'Request declined.');
    }

    /**
     * The provider identity this doctor acts as.
     *
     * Resolved rather than looked up: a doctor created by admin invite has no
     * `care_providers` row until something makes one, and refusing to act on a
     * request that was addressed to them is indistinguishable, from their side,
     * from the Accept button being broken.
     */
    private function myProvider(Request $request): CareProvider
    {
        return CareProvider::resolveForUser($request->user()->id);
    }
}
