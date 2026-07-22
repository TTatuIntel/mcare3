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

    public function resolve(Request $request, SosEvent $event)
    {
        DoctorAccess::assertCaseload($request->user(), $event->user_id);

        $data = $request->validate([
            'status' => 'required|string|in:acknowledged,resolved,falseAlarm',
            'responded_by' => 'nullable|string|max:120',
        ]);

        $doctor = $request->user();
        $event->update([
            'status' => $data['status'],
            'responded_by' => $data['responded_by']
                ?? 'Dr. '.$doctor->fullName(),
            'responded_at' => now(),
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
