<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\Medication;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorPrescriptionsController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|integer|exists:users,id',
            'name' => 'required|string|max:160',
            'dosage' => 'required|string|max:60',
            'frequency' => 'required|string|max:120',
            'form' => 'nullable|string|max:60',
            'instructions' => 'nullable|string',
            'start_date' => 'required|date',
            'end_date' => 'nullable|date|after_or_equal:start_date',
            'refills_left' => 'nullable|integer|min:0',
        ]);

        DoctorAccess::assertCaseload($request->user(), (int) $data['patient_user_id']);

        $med = Medication::create([
            'user_id' => $data['patient_user_id'],
            'name' => $data['name'],
            'dosage' => $data['dosage'],
            'frequency' => $data['frequency'],
            'form' => $data['form'] ?? null,
            'instructions' => $data['instructions'] ?? null,
            'prescribed_by' => 'Dr. '.$request->user()->fullName(),
            'prescribed_by_user_id' => $request->user()->id,
            'start_date' => $data['start_date'],
            'end_date' => $data['end_date'] ?? null,
            'refills_left' => $data['refills_left'] ?? 0,
            'source' => 'doctorPrescribed',
            'active' => true,
        ]);

        AppNotification::create([
            'user_id' => $data['patient_user_id'],
            'kind' => 'medication',
            'title' => 'New prescription',
            'body' => "Dr. {$request->user()->fullName()} prescribed {$med->name} {$med->dosage}.",
            'action_route' => '/patient/medications',
            'read' => false,
        ]);

        DoctorAccess::audit(
            $request->user(),
            'Issued prescription',
            "Patient #{$med->user_id} — {$med->name} {$med->dosage}"
        );

        return $this->success(['prescription' => $med->toApiArray()], 'Prescription issued.', 201);
    }

    public function revoke(Request $request, Medication $medication)
    {
        abort_unless(
            $medication->prescribed_by_user_id === $request->user()->id,
            403,
            'You can only revoke your own prescriptions.'
        );
        $medication->update(['active' => false]);
        DoctorAccess::audit(
            $request->user(),
            'Revoked prescription',
            "Patient #{$medication->user_id} — {$medication->name}"
        );
        return $this->success(['prescription' => $medication->fresh()->toApiArray()], 'Prescription revoked.');
    }
}
