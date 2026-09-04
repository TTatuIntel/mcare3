<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\EmergencyContact;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Clinical patient views for admin / mCare assistant staff.
 *
 * `show` returns the same shape as the doctor patient endpoint so the
 * shared StaffPatientProfileSheet renders identically for both audiences.
 * `updateAssignedVitals` lets admin assist a patient when the doctor / care
 * team is unavailable — bypasses `DoctorAccess::assertCaseload` and audits
 * the change explicitly.
 */
class PatientsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

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

    /**
     * Assign or reassign the vitals a patient must track. Mirrors the doctor
     * endpoint but is scoped to admin/mcare_assistant so care staff can
     * intervene when the assigned doctor is unavailable or the patient
     * requests assistance.
     */
    public function updateAssignedVitals(Request $request, User $patient)
    {
        abort_unless($patient->role === 'patient', 404, 'Not a patient account.');

        $data = $request->validate([
            'assigned_vitals' => 'required|array|min:1',
            'assigned_vitals.*' => 'string',
        ]);

        $allowed = VitalCatalog::where('enabled', true)
            ->pluck('vital_key')
            ->all();

        $keys = collect($data['assigned_vitals'])
            ->unique()
            ->values()
            ->all();

        foreach ($keys as $key) {
            abort_unless(
                in_array($key, $allowed, true),
                422,
                "Unknown or disabled vital: {$key}"
            );
        }

        $before = $patient->assignedVitals()->pluck('vital_key')->all();

        DB::transaction(function () use ($patient, $keys, $before) {
            $patient->assignedVitals()->delete();
            foreach ($keys as $vitalKey) {
                $patient->assignedVitals()->create(['vital_key' => $vitalKey]);
            }

            $added = array_values(array_diff($keys, $before));
            $removed = array_values(array_diff($before, $keys));

            foreach ($added as $vitalKey) {
                $patient->trackedVitals()->firstOrCreate(['vital_key' => $vitalKey]);
            }
            foreach ($removed as $vitalKey) {
                $patient->trackedVitals()->where('vital_key', $vitalKey)->delete();
            }
        });

        $added = array_values(array_diff($keys, $before));
        $removed = array_values(array_diff($before, $keys));

        if (! empty($added) || ! empty($removed)) {
            $actor = $request->user();
            $actorLabel = ($actor->role === 'admin' ? 'Admin ' : 'mCare ')
                .$actor->fullName();
            $parts = [];
            if (! empty($added)) {
                $parts[] = 'assigned: '.implode(', ', $added);
            }
            if (! empty($removed)) {
                $parts[] = 'removed: '.implode(', ', $removed);
            }

            AppNotification::create([
                'user_id' => $patient->id,
                'kind' => 'assignment',
                'title' => 'Vitals updated by '.$actorLabel,
                'body' => $actorLabel.' updated your required vitals ('.implode('; ', $parts).').',
                'action_route' => '/patient/vitals',
                'read' => false,
            ]);

            $this->audit->record(
                $actor,
                'patient.vitals_assigned',
                'Updated assigned vitals for '.$patient->fullName().' — '.implode('; ', $parts),
                'activity',
                [
                    'patient_user_id' => $patient->id,
                    'added' => $added,
                    'removed' => $removed,
                ],
            );
        }

        return $this->success([
            'assigned_vitals' => $keys,
        ], 'Assigned vitals updated.');
    }
}
