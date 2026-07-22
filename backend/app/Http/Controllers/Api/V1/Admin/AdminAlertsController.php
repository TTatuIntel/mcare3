<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use App\Support\VitalAlertPayload;
use Illuminate\Http\Request;

/**
 * System-wide vital alerts for admin / assistant staff.
 * Mirrors DoctorAlertsController but spans all patient accounts.
 */
class AdminAlertsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $patientIds = User::where('role', 'patient')->pluck('id');

        $query = AppNotification::whereIn('user_id', $patientIds)
            ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
            ->orderByDesc('created_at');

        if ($request->boolean('open_only')) {
            $query->where('resolved', false);
        }

        $patients = User::whereIn('id', $patientIds)->get()->keyBy('id');

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
        $this->assertVitalAlert($alert);

        $alert->update(['read' => true]);

        $this->audit->record(
            $request->user(),
            'alert.acknowledged',
            "Alert #{$alert->id}",
            'activity',
            ['alert_id' => $alert->id, 'patient_user_id' => $alert->user_id],
        );

        return $this->success(['alert' => $alert->fresh()->toApiArray()], 'Alert acknowledged.');
    }

    public function resolve(Request $request, AppNotification $alert)
    {
        $this->assertVitalAlert($alert);

        $data = $request->validate([
            'action_taken' => 'required|string|in:patient_contacted,medication_adjusted,follow_up_scheduled,monitored,referred,reading_error,other',
            'custom_action' => 'required_if:action_taken,other|nullable|string|min:3|max:120',
            'note' => 'required|string|min:4|max:500',
        ]);

        $args = is_array($alert->action_arguments) ? $alert->action_arguments : [];
        $args['resolution_action'] = $data['action_taken'];
        $args['resolution_note'] = $data['note'];
        if ($data['action_taken'] === 'other' && ! empty($data['custom_action'])) {
            $args['resolution_custom_action'] = $data['custom_action'];
        }

        $alert->update([
            'read' => true,
            'resolved' => true,
            'resolved_at' => now(),
            'action_arguments' => $args,
        ]);

        $this->audit->record(
            $request->user(),
            'alert.resolved',
            "Alert #{$alert->id} — {$data['action_taken']}: {$data['note']}",
            'activity',
            ['alert_id' => $alert->id, 'patient_user_id' => $alert->user_id],
        );

        return $this->success(['alert' => $alert->fresh()->toApiArray()], 'Alert resolved.');
    }

    private function assertVitalAlert(AppNotification $alert): void
    {
        if (! in_array($alert->kind, ['vital_warning', 'vital_critical', 'sos'], true)) {
            abort(404);
        }

        $owner = User::find($alert->user_id);
        if (! $owner || $owner->role !== 'patient') {
            abort(404);
        }
    }
}
