<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class AppointmentsController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'doctor_name' => 'required|string|max:160',
            'doctor_user_id' => 'nullable|exists:users,id',
            'doctor_specialty' => 'nullable|string|max:120',
            'scheduled_at' => 'required|date',
            'duration_minutes' => 'nullable|integer|min:5|max:480',
            'type' => 'nullable|string|in:inPerson,virtual,phone',
            'reason' => 'nullable|string|max:200',
            'location_or_link' => 'nullable|string|max:500',
        ]);
        $appt = $request->user()->appointments()->create([
            ...$data,
            'type' => $data['type'] ?? 'inPerson',
            'duration_minutes' => $data['duration_minutes'] ?? 30,
            'status' => 'scheduled',
        ]);
        return $this->success(['appointment' => $appt->toApiArray()], 'Appointment scheduled.', 201);
    }

    public function update(Request $request, Appointment $appointment)
    {
        $this->authorizeOwnership($request, $appointment);
        $data = $request->validate([
            'status' => 'nullable|string|in:scheduled,confirmed,completed,cancelled',
            'scheduled_at' => 'nullable|date',
            'cancellation_reason' => 'nullable|string|max:200',
        ]);
        $appointment->update(array_filter($data, fn ($v) => $v !== null));
        return $this->success(['appointment' => $appointment->fresh()->toApiArray()], 'Appointment updated.');
    }

    public function destroy(Request $request, Appointment $appointment)
    {
        $this->authorizeOwnership($request, $appointment);
        $appointment->update(['status' => 'cancelled']);
        return $this->success(null, 'Appointment cancelled.');
    }

    private function authorizeOwnership(Request $request, Appointment $appt): void
    {
        abort_unless($appt->user_id === $request->user()->id, 403, 'Not allowed.');
    }
}
