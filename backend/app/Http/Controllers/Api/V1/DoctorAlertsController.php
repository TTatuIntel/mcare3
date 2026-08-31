<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\AlertResolutionNotifier;
use App\Support\ApiResponse;
use App\Support\VitalAlertPayload;
use Illuminate\Http\Request;

class DoctorAlertsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $patientIds = DoctorAccess::caseloadPatientIds($request->user());
        $query = AppNotification::whereIn('user_id', $patientIds)
            ->whereIn('kind', AlertResolutionNotifier::KINDS)
            ->orderByDesc('created_at');

        if ($request->boolean('open_only')) {
            // Open means unresolved, not unread. A doctor who acknowledges an
            // alert has said "I have seen this", not "this is dealt with" —
            // filtering on `read` made the alert vanish from the very list the
            // doctor works from the moment they touched it.
            $query->where('resolved', false);
        }

        $patients = User::whereIn('id', $patientIds)
            ->get()
            ->keyBy('id');

        return $this->success([
            'alerts' => $query->limit(200)->get()->map(function (AppNotification $n) use ($patients) {
                $patient = $patients->get($n->user_id);

                return VitalAlertPayload::alertToApiArray($n, [
                    'patient_id' => (string) $n->user_id,
                    'patient_name' => $patient ? $patient->fullName() : '',
                ]);
            })->all(),
        ]);
    }

    public function acknowledge(Request $request, AppNotification $alert)
    {
        DoctorAccess::assertCaseload($request->user(), $alert->user_id);

        $alert = AlertResolutionNotifier::acknowledge($alert, $request->user());

        DoctorAccess::audit($request->user(), 'Acknowledged alert', "Alert #{$alert->id}");

        return $this->success(['alert' => $alert->toApiArray()], 'Alert acknowledged.');
    }

    public function resolve(Request $request, AppNotification $alert)
    {
        DoctorAccess::assertCaseload($request->user(), $alert->user_id);

        $data = $request->validate([
            'action_taken' => 'required|string|in:'.implode(',', AlertResolutionNotifier::ACTIONS),
            'custom_action' => 'required_if:action_taken,other|nullable|string|min:3|max:120',
            'note' => 'required|string|min:4|max:500',
        ]);

        $alert = AlertResolutionNotifier::resolve(
            $alert,
            $request->user(),
            $data['action_taken'],
            $data['custom_action'] ?? null,
            $data['note'],
        );

        DoctorAccess::audit(
            $request->user(),
            'Resolved alert',
            "Alert #{$alert->id} — {$data['action_taken']}: {$data['note']}"
        );

        return $this->success(['alert' => $alert->toApiArray()], 'Alert resolved.');
    }
}
