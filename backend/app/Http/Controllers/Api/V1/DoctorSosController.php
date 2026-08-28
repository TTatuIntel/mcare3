<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\SosEvent;
use App\Services\SosNotifier;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorSosController extends Controller
{
    use ApiResponse;

    /**
     * The doctor's own emergencies, with the response trail attached.
     *
     * The session payload carries the live ones only, so an emergency
     * disappeared the moment it was closed — a doctor could not check what
     * had been done on the case they were handed, or what the outcome
     * eventually was. `status=all` is what makes follow-up possible.
     */
    public function index(Request $request)
    {
        $data = $request->validate([
            'status' => 'nullable|string|in:active,all,resolved,falseAlarm,acknowledged',
        ]);

        $patientIds = DoctorAccess::caseloadPatientIds($request->user());
        if ($patientIds === []) {
            return $this->success(['sos_events' => []]);
        }

        $status = $data['status'] ?? 'active';
        $query = SosEvent::with(['user', 'responseActions.user'])
            ->whereIn('user_id', $patientIds)
            ->orderByDesc('triggered_at');

        if ($status === 'active') {
            $query->whereIn('status', ['active', 'acknowledged']);
        } elseif ($status !== 'all') {
            $query->where('status', $status);
        }

        $events = $query->limit(200)->get()->map(function (SosEvent $e) {
            $arr = $e->toApiArray();
            $arr['patient_id'] = (string) $e->user_id;
            $arr['patient_name'] = $e->user?->fullName() ?? '';

            return $arr;
        });

        return $this->success(['sos_events' => $events]);
    }

    public function resolve(Request $request, SosEvent $event)
    {
        DoctorAccess::assertCaseload($request->user(), $event->user_id);

        $data = $request->validate([
            'status' => 'required|string|in:acknowledged,resolved,falseAlarm',
            'responded_by' => 'nullable|string|max:120',
            'resolution' => 'nullable|string|in:'.implode(',', SosEvent::RESOLUTIONS),
            // Picking "other" means the list did not fit, so the responder
            // has to say what did. Anything else may still carry detail.
            'resolution_note' => 'required_if:resolution,other|nullable|string|max:400',
        ]);

        $doctor = $request->user();
        $event->update([
            'status' => $data['status'],
            'responded_by' => $data['responded_by']
                ?? 'Dr. '.$doctor->fullName(),
            'responded_at' => now(),
            // Only a closing status carries an outcome; acknowledging is not
            // an ending and must not stamp one.
            'resolution' => $data['status'] === 'acknowledged'
                ? null
                : ($data['status'] === 'falseAlarm'
                    ? 'other'
                    : ($data['resolution'] ?? null)),
            'resolution_note' => $data['status'] === 'acknowledged'
                ? null
                : ($data['resolution_note'] ?? null),
        ]);

        SosNotifier::onResolved($event->fresh(), $data['status'], $doctor);

        $actionLabel = match ($data['status']) {
            'acknowledged' => 'Acknowledged SOS',
            'falseAlarm' => 'Marked SOS false alarm',
            default => 'Resolved SOS',
        };

        DoctorAccess::audit(
            $doctor,
            $actionLabel,
            $event->user->fullName().' · '.$data['status'],
            'sos'
        );

        return $this->success(
            ['event' => $event->fresh()->toApiArray()],
            'SOS updated.'
        );
    }
}
