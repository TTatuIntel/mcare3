<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\EmergencyContact;
use App\Models\User;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Read-only clinical profile for admin / mCare assistant staff.
 */
class PatientsController extends Controller
{
    use ApiResponse;

    public function show(Request $request, User $patient)
    {
        abort_unless($patient->role === 'patient', 404, 'Not a patient account.');

        $patient->load(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        return $this->success([
            'patient' => [
                'id' => (string) $patient->id,
                'unique_id' => $patient->unique_id,
                'name' => $patient->fullName(),
                'email' => $patient->email,
                'phone' => $patient->phone,
                'approval_status' => $patient->approval_status,
                'created_at' => $patient->created_at?->toIso8601String(),
            ],
            'has_health_profile' => $patient->healthProfile !== null,
            'health' => $patient->healthProfile?->toApiArray(),
            'emergency_contacts' => $patient->emergencyContacts
                ->map(fn (EmergencyContact $c) => $c->toApiArray())
                ->values()
                ->all(),
            'assigned_vitals' => $patient->assignedVitals
                ->pluck('vital_key')
                ->values()
                ->all(),
        ]);
    }
}
