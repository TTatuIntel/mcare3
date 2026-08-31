<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\CareProvider;
use App\Services\WorkflowNotificationService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorAppointmentsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date|after_or_equal:from',
        ]);
        $query = Appointment::where('doctor_user_id', $request->user()->id)
            ->orderBy('scheduled_at');
        if ($request->filled('from')) {
            $query->where('scheduled_at', '>=', $request->date('from'));
        }
        if ($request->filled('to')) {
            $query->where('scheduled_at', '<=', $request->date('to'));
        }
        return $this->success([
            'appointments' => $query->limit(500)->get()->map->toApiArray()->all(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|integer|exists:users,id',
            'scheduled_at' => 'required|date|after:now',
            'duration_minutes' => 'nullable|integer|min:5|max:480',
            'type' => 'nullable|string|in:inPerson,virtual,phone',
            'reason' => 'nullable|string|max:200',
            'location_or_link' => 'nullable|string|max:500',
        ]);
        DoctorAccess::assertCaseload($request->user(), (int) $data['patient_user_id']);

        $doctor = $request->user();
        $provider = CareProvider::where('user_id', $doctor->id)->first();
        $appt = Appointment::create([
            'user_id' => $data['patient_user_id'],
            'doctor_user_id' => $doctor->id,
            'doctor_name' => 'Dr. '.$doctor->fullName(),
            'doctor_specialty' => $provider?->specialty,
            'scheduled_at' => $data['scheduled_at'],
            'duration_minutes' => $data['duration_minutes'] ?? 30,
            'type' => $data['type'] ?? 'inPerson',
            'status' => 'scheduled',
            'reason' => $data['reason'] ?? null,
            'location_or_link' => $data['location_or_link'] ?? null,
        ]);

        WorkflowNotificationService::appointmentChanged($appt, $doctor, 'created');
        DoctorAccess::audit(
            $doctor,
            'Scheduled appointment',
            "Patient #{$appt->user_id} — {$appt->scheduled_at->toIso8601String()}"
        );

        return $this->success(['appointment' => $appt->toApiArray()], 'Appointment scheduled.', 201);
    }

    public function update(Request $request, Appointment $appointment)
    {
        abort_unless(
            $appointment->doctor_user_id === $request->user()->id,
            403,
            'Not your appointment.'
        );
        $data = $request->validate([
            'status' => 'nullable|string|in:scheduled,confirmed,completed,cancelled',
            'scheduled_at' => 'nullable|date',
            'cancellation_reason' => 'nullable|string|max:200',
        ]);
        $appointment->update(array_filter($data, fn ($v) => $v !== null));
        WorkflowNotificationService::appointmentChanged(
            $appointment->fresh(),
            $request->user(),
            $appointment->status === 'cancelled' ? 'cancelled' : 'updated',
        );
        DoctorAccess::audit(
            $request->user(),
            'Updated appointment',
            "Appointment #{$appointment->id} → {$appointment->status}"
        );
        return $this->success(['appointment' => $appointment->fresh()->toApiArray()], 'Appointment updated.');
    }
}
