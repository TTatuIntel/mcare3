<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\EmergencyContact;
use App\Models\VitalCatalog;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Returns the full patient session in a single payload — vitals,
 * meds, appts, docs, messages, notifications, support, sos, care team,
 * vital-report requests, settings.
 *
 * Mirrors the shape MockBootstrap::seedPatientSession() produces in
 * the Flutter mock layer so the existing widgets keep working.
 */
class PatientSessionController extends Controller
{
    use ApiResponse;

    public function show(Request $request)
    {
        $user = $request->user();
        $user->load([
            'healthProfile',
            'emergencyContacts',
            'assignedVitals',
            'trackedVitals',
        ]);

        $payload = [
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

            'tracked_vitals' => $this->resolveTrackedVitals($user),

            'vital_catalog' => VitalCatalog::where('enabled', true)
                ->orderBy('vital_key')
                ->get()
                ->map->toApiArray()
                ->all(),

            'vitals' => $user->vitalReadings()
                ->orderByDesc('recorded_at')
                ->limit(500)
                ->get()
                ->map->toApiArray()
                ->all(),

            'medications' => $user->medications()
                ->where('active', true)
                ->orderByDesc('start_date')
                ->get()
                ->map->toApiArray()
                ->all(),

            'medication_doses' => $user->medicationDoses()
                ->whereBetween('scheduled_at', [now()->subDays(7), now()->addDays(7)])
                ->orderBy('scheduled_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'appointments' => $user->appointments()
                ->orderBy('scheduled_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'documents' => $user->medicalDocuments()
                ->orderByDesc('uploaded_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'conversations' => $user->conversations()
                ->with(['messages' => fn ($q) => $q->orderByDesc('sent_at')->limit(1)])
                ->withCount(['messages as unread_messages_count' => fn ($q) => $q
                    ->where('sender_user_id', '!=', $user->id)
                    ->where('read', false)])
                ->withMax('messages', 'sent_at')
                ->orderByDesc('messages_max_sent_at')
                ->get()
                ->map(fn ($conversation) => $conversation->toApiArray($user))
                ->all(),

            'notifications' => $user->appNotifications()
                ->orderByDesc('created_at')
                ->limit(100)
                ->get()
                ->map->toApiArray()
                ->all(),

            'support_tickets' => $user->supportTickets()
                ->orderByDesc('updated_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'sos_history' => $user->sosEvents()
                ->orderByDesc('triggered_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'care_providers' => $this->careProvidersFor($user->id),

            'care_requests' => $user->careRequests()
                ->orderByDesc('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'vital_report_requests' => $user->vitalReportRequests()
                ->orderByDesc('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),
        ];

        return $this->success($payload);
    }

    /**
     * Tracked vitals always include clinician-assigned ones.
     * When the patient has never saved preferences, fall back to assigned only.
     */
    private function resolveTrackedVitals($user): array
    {
        $assigned = $user->assignedVitals->pluck('vital_key');
        $tracked = $user->trackedVitals->pluck('vital_key');

        if ($tracked->isEmpty()) {
            return $assigned->values()->all();
        }

        return $tracked->merge($assigned)->unique()->values()->all();
    }

    private function careProvidersFor(int $userId): array
    {
        $assignedIds = CareAssignment::where('patient_user_id', $userId)
            ->whereNull('ended_at')
            ->pluck('provider_id')
            ->flip();

        return CareProvider::orderBy('name')
            ->get()
            ->map(function (CareProvider $provider) use ($assignedIds) {
                $row = $provider->toApiArray();
                $row['assigned'] = isset($assignedIds[$provider->id]);

                return $row;
            })
            ->all();
    }
}
