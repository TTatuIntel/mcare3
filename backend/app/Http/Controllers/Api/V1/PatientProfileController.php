<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\EmergencyContact;
use App\Models\PatientAssignedVital;
use App\Models\PatientHealthProfile;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PatientProfileController extends Controller
{
    use ApiResponse;

    public function show(Request $request)
    {
        $user = $request->user();
        $user->load(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        return $this->success($this->profilePayload($user));
    }

    public function updateAccount(Request $request)
    {
        $data = $request->validate([
            'first_name' => 'required|string|max:100',
            'last_name' => 'required|string|max:100',
            'phone' => 'nullable|string|max:30',
        ]);

        $user = $request->user();
        $user->update([
            'first_name' => $data['first_name'],
            'last_name' => $data['last_name'],
            'phone' => $data['phone'] ?? null,
        ]);

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
        ], 'Account updated.');
    }

    public function updateHealth(Request $request)
    {
        $data = $request->validate([
            'blood_type' => 'required|string',
            'gender' => 'required|string',
            'date_of_birth' => 'required|date',
            'height_cm' => 'required|numeric|min:1',
            'weight_kg' => 'required|numeric|min:1',
            'allergies' => 'nullable|array',
            'chronic_conditions' => 'nullable|array',
            'current_medications' => 'nullable|array',
            'address' => 'nullable|string|max:500',
            'location_consent' => 'boolean',
            'no_known_allergies' => 'boolean',
            'no_current_medications' => 'boolean',
            'assigned_vitals' => 'nullable|array',
            'assigned_vitals.*' => 'string',
        ]);

        $user = $request->user();
        $profile = $user->healthProfile;

        if (! $profile) {
            return $this->error('Complete onboarding first.', 404);
        }

        $assignedVitals = $data['assigned_vitals'] ?? null;
        unset($data['assigned_vitals']);

        DB::transaction(function () use ($user, $profile, $data, $assignedVitals) {
            $profile->update($data);

            // When the patient edits their monitoring plan, re-sync the
            // assigned + tracked vital sets (mirrors onboarding).
            if ($assignedVitals !== null) {
                $user->assignedVitals()->delete();
                $user->trackedVitals()->delete();
                foreach ($assignedVitals as $vitalKey) {
                    $user->assignedVitals()->create(['vital_key' => $vitalKey]);
                    $user->trackedVitals()->create(['vital_key' => $vitalKey]);
                }
            }
        });

        $user->load('assignedVitals');

        return $this->success([
            'health' => $profile->fresh()->toApiArray(),
            'assigned_vitals' => $user->assignedVitals
                ->pluck('vital_key')
                ->values()
                ->all(),
        ], 'Health profile updated.');
    }

    public function completeOnboarding(Request $request)
    {
        $data = $request->validate([
            'health' => 'required|array',
            'health.blood_type' => 'required|string',
            'health.gender' => 'required|string',
            'health.date_of_birth' => 'required|date',
            'health.height_cm' => 'required|numeric|min:1',
            'health.weight_kg' => 'required|numeric|min:1',
            'health.allergies' => 'nullable|array',
            'health.chronic_conditions' => 'nullable|array',
            'health.current_medications' => 'nullable|array',
            'health.address' => 'nullable|string|max:500',
            'health.location_consent' => 'boolean',
            'health.no_known_allergies' => 'boolean',
            'health.no_current_medications' => 'boolean',
            'emergency_contacts' => 'required|array|min:1',
            'emergency_contacts.*.name' => 'required|string|max:120',
            'emergency_contacts.*.relationship' => 'required|string|max:80',
            'emergency_contacts.*.phone' => 'required|string|max:30',
            'emergency_contacts.*.email' => 'nullable|email',
            'emergency_contacts.*.priority' => 'nullable|integer|min:1',
            'assigned_vitals' => 'required|array|min:1',
            'assigned_vitals.*' => 'string',
        ]);

        $user = $request->user();

        DB::transaction(function () use ($user, $data) {
            PatientHealthProfile::updateOrCreate(
                ['user_id' => $user->id],
                $data['health'],
            );

            $user->emergencyContacts()->delete();
            foreach ($data['emergency_contacts'] as $contact) {
                $user->emergencyContacts()->create([
                    'name' => $contact['name'],
                    'relationship' => $contact['relationship'],
                    'phone' => $contact['phone'],
                    'email' => $contact['email'] ?? null,
                    'priority' => $contact['priority'] ?? 1,
                ]);
            }

            $user->assignedVitals()->delete();
            $user->trackedVitals()->delete();
            foreach ($data['assigned_vitals'] as $vitalKey) {
                $user->assignedVitals()->create(['vital_key' => $vitalKey]);
                $user->trackedVitals()->create(['vital_key' => $vitalKey]);
            }
        });

        $user->load(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        return $this->success($this->profilePayload($user), 'Onboarding complete.');
    }

    public function storeEmergencyContact(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:120',
            'relationship' => 'required|string|max:80',
            'phone' => 'required|string|max:30',
            'email' => 'nullable|email',
            'priority' => 'nullable|integer|min:1',
        ]);

        $user = $request->user();
        $contact = $user->emergencyContacts()->create([
            'name' => $data['name'],
            'relationship' => $data['relationship'],
            'phone' => $data['phone'],
            'email' => $data['email'] ?? null,
            'priority' => $data['priority'] ?? ($user->emergencyContacts()->count() + 1),
        ]);

        return $this->success(
            ['contact' => $contact->toApiArray()],
            'Emergency contact added.',
            201,
        );
    }

    public function destroyEmergencyContact(Request $request, EmergencyContact $contact)
    {
        abort_unless($contact->user_id === $request->user()->id, 403);
        $contact->delete();

        return $this->success(null, 'Emergency contact removed.');
    }

    private function profilePayload($user): array
    {
        return [
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile !== null,
            'health' => $user->healthProfile?->toApiArray(),
            'emergency_contacts' => $user->emergencyContacts
                ->map(fn (EmergencyContact $c) => $c->toApiArray())
                ->values()
                ->all(),
            'assigned_vitals' => $user->assignedVitals
                ->pluck('vital_key')
                ->values()
                ->all(),
        ];
    }
}
