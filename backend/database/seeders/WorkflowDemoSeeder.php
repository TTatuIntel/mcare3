<?php

namespace Database\Seeders;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\EmergencyContact;
use App\Models\ExternalAccessToken;
use App\Models\MealPlan;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Models\PatientReportRequest;
use App\Models\SosEvent;
use App\Models\SosResponseAction;
use App\Models\User;
use App\Models\UserInvite;
use App\Models\UserSetting;
use App\Models\VitalRangeOverride;
use App\Models\VitalReportRequest;
use App\Services\VitalReportIssuer;
use App\Support\MedicalDocumentFiles;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Completes the demonstration dataset across every durable application flow.
 *
 * Deliberately excluded: cache, sessions, queue jobs, password/verification
 * codes, API tokens, FCM device tokens, and derived staff notification state.
 * Those rows represent runtime infrastructure or secrets, not fixture data.
 */
class WorkflowDemoSeeder extends Seeder
{
    public function run(): void
    {
        $now = now();
        $admin = User::where('email', 'admin@mcare.health')->firstOrFail();
        $assistant = User::where('email', 'assistant@mcare.health')->firstOrFail();
        $fallbackDoctor = User::where('email', 'dr.mensah@mcare.health')->firstOrFail();

        $this->completeStaffProfiles($admin);
        $this->seedPreferencesAndRoleNotifications();

        $patients = User::query()
            ->where('role', 'patient')
            ->where('approval_status', 'active')
            ->orderBy('id')
            ->get();

        foreach ($patients as $index => $patient) {
            $doctor = $this->assignedDoctor($patient) ?? $fallbackDoctor;
            $this->seedPatientWorkflow($patient, $doctor, $index, $now);
        }

        $this->seedVitalOverrides($patients, $fallbackDoctor);
        $this->seedExternalAccess($patients->first(), $admin, $now);
        $this->seedPatientReportLifecycle($patients, $admin, $fallbackDoctor, $now);
        $this->seedSosResponseTrail($admin, $assistant);
        $this->seedPendingInvitations($now);
    }

    private function completeStaffProfiles(User $admin): void
    {
        $profiles = [
            'dr.mensah@mcare.health' => ['Internal medicine', 'KMPDC-DEMO-0231'],
            'dr.adeyemi@mcare.health' => ['Endocrinology', 'KMPDC-DEMO-0312'],
            'dr.kamau@mcare.health' => ['Family medicine', 'KMPDC-DEMO-P001'],
            'dr.wanjiru@mcare.health' => ['Cardiology', 'KMPDC-DEMO-P002'],
        ];

        foreach ($profiles as $email => [$specialty, $license]) {
            $doctor = User::where('email', $email)->first();
            if (! $doctor) {
                continue;
            }

            $updates = [
                'specialty' => $specialty,
                'license_number' => $license,
            ];
            if ($doctor->approval_status === 'active') {
                $updates += [
                    'approved_at' => $doctor->approved_at ?? now()->subMonths(6),
                    'approved_by' => $doctor->approved_by ?? $admin->id,
                    'approval_note' => $doctor->approval_note ?? 'Demo credential review completed.',
                ];
            }
            $doctor->update($updates);
        }
    }

    private function seedPreferencesAndRoleNotifications(): void
    {
        User::query()->orderBy('id')->each(function (User $user): void {
            UserSetting::updateOrCreate(
                ['user_id' => $user->id],
                ['payload' => [
                    'theme_mode' => 'system',
                    'language_code' => 'en',
                    'notifications' => [
                        'push' => true,
                        'email' => true,
                        'appointments' => true,
                        'messages' => true,
                        'medications' => $user->role === 'patient',
                        'vitals' => in_array($user->role, ['patient', 'doctor', 'admin', 'mcare_assistant'], true),
                        'sos' => true,
                    ],
                    'privacy_share_with_care_team' => $user->role === 'patient',
                    'privacy_allow_external_access' => $user->role === 'patient',
                ]],
            );

            AppNotification::updateOrCreate(
                [
                    'user_id' => $user->id,
                    'title' => 'Demo workspace ready',
                ],
                [
                    'kind' => 'system',
                    'body' => 'Your role-specific test data is available from the live API.',
                    'action_route' => $this->homeRoute($user->role),
                    'action_arguments' => ['dataset' => 'application-demo-v1'],
                    'read' => $user->approval_status !== 'active',
                    'resolved' => false,
                ],
            );
        });
    }

    private function seedPatientWorkflow(
        User $patient,
        User $doctor,
        int $index,
        Carbon $now,
    ): void {
        if (! EmergencyContact::where('user_id', $patient->id)->exists()) {
            EmergencyContact::create([
                'user_id' => $patient->id,
                'name' => 'Emergency Contact '.$patient->first_name,
                'relationship' => 'Family',
                'phone' => '+254 700 '.str_pad((string) $patient->id, 6, '0', STR_PAD_LEFT),
                'email' => 'contact.'.$patient->id.'@example.test',
                'priority' => 1,
            ]);
        }

        $medication = Medication::firstOrCreate(
            ['user_id' => $patient->id, 'name' => 'Demo care-plan supplement'],
            [
                'dosage' => '1 tablet',
                'frequency' => 'Once daily',
                'form' => 'Tablet',
                'instructions' => 'Take with breakfast during the test period.',
                'prescribed_by' => 'Dr. '.$doctor->fullName(),
                'prescribed_by_user_id' => $doctor->id,
                'start_date' => $now->copy()->subDays(14),
                'expiry_date' => $now->copy()->addMonths(3),
                'refills_left' => 2,
                'source' => 'doctorPrescribed',
                'active' => true,
            ],
        );

        MedicationDose::updateOrCreate(
            [
                'medication_id' => $medication->id,
                'user_id' => $patient->id,
                'scheduled_at' => $now->copy()->startOfDay()->addHours(8),
            ],
            [
                'status' => $index % 3 === 0 ? 'taken' : ($index % 3 === 1 ? 'pending' : 'missed'),
                'taken_at' => $index % 3 === 0
                    ? $now->copy()->startOfDay()->addHours(8)->addMinutes(5)
                    : null,
            ],
        );

        Appointment::updateOrCreate(
            ['user_id' => $patient->id, 'reason' => 'Seeded comprehensive care-plan review'],
            [
                'doctor_user_id' => $doctor->id,
                'doctor_name' => 'Dr. '.$doctor->fullName(),
                'doctor_specialty' => $doctor->specialty,
                'scheduled_at' => $now->copy()->addDays(2 + $index)->setTime(9 + ($index % 4), 30),
                'duration_minutes' => 30,
                'type' => $index % 2 === 0 ? 'virtual' : 'inPerson',
                'status' => 'confirmed',
                'location_or_link' => $index % 2 === 0
                    ? 'https://meet.mcare.health/demo-'.$patient->id
                    : 'mCare Clinical Centre, Room '.(10 + $index),
            ],
        );

        Appointment::updateOrCreate(
            ['user_id' => $patient->id, 'reason' => 'Seeded completed clinical check-in'],
            [
                'doctor_user_id' => $doctor->id,
                'doctor_name' => 'Dr. '.$doctor->fullName(),
                'doctor_specialty' => $doctor->specialty,
                'scheduled_at' => $now->copy()->subDays(5 + $index)->setTime(11, 0),
                'duration_minutes' => 30,
                'type' => 'phone',
                'status' => 'completed',
                'location_or_link' => null,
            ],
        );

        MealPlan::updateOrCreate(
            ['patient_user_id' => $patient->id, 'title' => 'Balanced metabolic care plan'],
            [
                'assigned_by_user_id' => $doctor->id,
                'meal_type' => 'daily',
                'description' => 'High-fibre meals with lean protein and controlled portions.',
                'calories' => 1900 + ($index * 50),
                'protein' => '95 g',
                'carbs' => '210 g',
                'fat' => '65 g',
                'notes' => 'Use as test data only; this is not medical advice.',
                'assigned_at' => $now->copy()->subDays(3),
            ],
        );

        $documentTitle = 'Seeded care summary — '.$patient->unique_id;
        if (! MedicalDocument::where('user_id', $patient->id)->where('title', $documentTitle)->exists()) {
            $stored = MedicalDocumentFiles::storeFixtureCopy($patient->id, $documentTitle, 'pdf');
            MedicalDocument::create([
                'user_id' => $patient->id,
                'title' => $documentTitle,
                'category' => 'consultationNote',
                'file_type' => 'pdf',
                'storage_path' => $stored['path'],
                'size_bytes' => $stored['size'],
                'uploaded_by' => 'Dr. '.$doctor->fullName(),
                'description' => 'Generated document fixture for download and preview testing.',
                'shared_with_doctor_id' => $doctor->id,
                'uploaded_at' => $now->copy()->subDays(2),
            ]);
        }

        $conversation = Conversation::updateOrCreate(
            ['user_id' => $patient->id, 'participant_user_id' => $doctor->id],
            [
                'participant_name' => 'Dr. '.$doctor->fullName(),
                'participant_role' => 'doctor',
                'participant_specialty' => $doctor->specialty,
            ],
        );
        ChatMessage::updateOrCreate(
            [
                'conversation_id' => $conversation->id,
                'body' => 'Your care-plan review is ready. Please check the latest readings before our appointment.',
            ],
            [
                'sender_user_id' => $doctor->id,
                'read' => false,
                'sent_at' => $now->copy()->subMinutes(15 + $index),
            ],
        );

        $fulfilled = $index % 2 !== 0;

        $vitalRequest = VitalReportRequest::updateOrCreate(
            ['user_id' => $patient->id, 'note' => 'Seeded 30-day trend review'],
            [
                'range_from' => $now->copy()->subDays(30)->toDateString(),
                'range_to' => $now->toDateString(),
                'vitals' => ['bloodPressure', 'heartRate'],
                'status' => $fulfilled ? 'fulfilled' : 'pending',
                'current_responder' => $fulfilled ? 'mcareAssistant' : 'doctor',
                'responded_at' => $fulfilled ? $now->copy()->subDay() : null,
                'responded_by' => $fulfilled ? 'Dr. '.$doctor->fullName() : null,
                'response_note' => $fulfilled
                    ? 'Trends reviewed; continue the current plan.'
                    : null,
                // Fulfilling is signing. Seeding the status without it produced
                // a report that rendered "this copy was made before it was
                // signed" — an unsigned clinical document in the demo.
                'signed_by_user_id' => $fulfilled ? $doctor->id : null,
                'signed_by' => $fulfilled ? 'Dr. '.$doctor->fullName() : null,
                'signed_by_role' => $fulfilled ? 'doctor' : null,
                'signed_at' => $fulfilled ? $now->copy()->subDay() : null,
            ],
        );

        // A seeded "fulfilled" request used to be a status and nothing else:
        // the patient was shown a report as ready and had nothing to open,
        // which is the exact failure the real fulfil path exists to avoid.
        if ($fulfilled && ! $vitalRequest->document_id) {
            $document = app(VitalReportIssuer::class)->issue(
                $vitalRequest,
                $doctor,
                'Dr. '.$doctor->fullName(),
                'Trends reviewed; continue the current plan.',
            );

            if ($document !== null) {
                $vitalRequest->update(['document_id' => $document->id]);
            }
        }

        AppNotification::updateOrCreate(
            ['user_id' => $patient->id, 'title' => 'Care-plan review scheduled'],
            [
                'kind' => 'appointment',
                'body' => 'A follow-up with Dr. '.$doctor->fullName().' is ready for testing.',
                'action_route' => '/patient/appointments',
                'action_arguments' => ['source' => 'workflow_seeder'],
                'read' => false,
                'resolved' => false,
            ],
        );
    }

    private function seedVitalOverrides($patients, User $doctor): void
    {
        foreach ($patients->take(2) as $patient) {
            VitalRangeOverride::updateOrCreate(
                ['user_id' => $patient->id, 'vital_key' => 'bloodGlucose'],
                [
                    'normal_min' => 70,
                    'normal_max' => 120,
                    'warning_low' => 60,
                    'warning_high' => 180,
                    'critical_low' => 50,
                    'critical_high' => 250,
                    'set_by_user_id' => $doctor->id,
                ],
            );
        }
    }

    private function seedExternalAccess(?User $patient, User $admin, Carbon $now): void
    {
        if (! $patient) {
            return;
        }

        ExternalAccessToken::updateOrCreate(
            ['token' => hash('sha256', 'mcare-demo-external-access-'.$patient->id)],
            [
                'patient_user_id' => $patient->id,
                'created_by_user_id' => $admin->id,
                'access_code' => 'DEMO-'.str_pad((string) $patient->id, 4, '0', STR_PAD_LEFT),
                'label' => 'Seeded external consultation',
                'expires_at' => $now->copy()->addDays(7),
                'revoked_at' => null,
            ],
        );
    }

    private function seedPatientReportLifecycle($patients, User $admin, User $doctor, Carbon $now): void
    {
        $stages = [
            PatientReportRequest::STATUS_PENDING_CONSENT,
            PatientReportRequest::STATUS_PENDING_SIGNATURE,
            PatientReportRequest::STATUS_ISSUED,
            PatientReportRequest::STATUS_DECLINED,
            PatientReportRequest::STATUS_DRAFT,
        ];

        foreach ($patients as $index => $patient) {
            $status = $stages[$index % count($stages)];
            $reportDoctor = $this->assignedDoctor($patient) ?? $doctor;
            $consented = in_array($status, [
                PatientReportRequest::STATUS_PENDING_SIGNATURE,
                PatientReportRequest::STATUS_ISSUED,
            ], true);
            $issued = $status === PatientReportRequest::STATUS_ISSUED;

            PatientReportRequest::updateOrCreate(
                [
                    'patient_user_id' => $patient->id,
                    'title' => 'Seeded continuity-of-care report',
                ],
                [
                    'requested_by_user_id' => $admin->id,
                    'doctor_user_id' => $reportDoctor->id,
                    'purpose' => 'End-to-end consent, signature, issue, and revocation testing.',
                    'recipient' => 'Demo receiving facility',
                    'sections' => ['identity', 'care_team', 'health_profile', 'vitals_summary', 'medications'],
                    'consent_required' => true,
                    'signature_required' => true,
                    'status' => $status,
                    'consent_code_hash' => $status === PatientReportRequest::STATUS_PENDING_CONSENT
                        ? Hash::make('246810')
                        : null,
                    'consent_token' => $status === PatientReportRequest::STATUS_PENDING_CONSENT
                        ? hash('sha256', 'mcare-demo-consent-'.$patient->id)
                        : null,
                    'consent_channel' => 'email',
                    'consent_sent_at' => $status === PatientReportRequest::STATUS_PENDING_CONSENT
                        ? $now->copy()->subMinutes(20)
                        : null,
                    'consent_expires_at' => $status === PatientReportRequest::STATUS_PENDING_CONSENT
                        ? $now->copy()->addHours(23)
                        : null,
                    'consent_attempts' => 0,
                    'consented_at' => $consented ? $now->copy()->subDays(2) : null,
                    'consent_method' => $consented ? 'email_code' : null,
                    'declined_at' => $status === PatientReportRequest::STATUS_DECLINED
                        ? $now->copy()->subDay()
                        : null,
                    'decline_reason' => $status === PatientReportRequest::STATUS_DECLINED
                        ? 'Patient declined this demonstration request.'
                        : null,
                    'signed_at' => $issued ? $now->copy()->subDay() : null,
                    'signature_name' => $issued ? 'Dr. '.$reportDoctor->fullName() : null,
                    'signature_note' => $issued ? 'Reviewed for demonstration use.' : null,
                    'issued_at' => $issued ? $now->copy()->subHours(12) : null,
                    'snapshot' => $issued
                        ? json_encode(['version' => 1, 'source' => 'workflow_seeder'], JSON_THROW_ON_ERROR)
                        : null,
                ],
            );
        }
    }

    private function seedSosResponseTrail(User $admin, User $assistant): void
    {
        SosEvent::query()->orderBy('id')->limit(4)->get()->each(
            function (SosEvent $event, int $index) use ($admin, $assistant): void {
                $actor = $index % 2 === 0 ? $assistant : $admin;
                $actions = [
                    ['opened_response', 'Responder opened the live emergency workspace.'],
                    ['viewed_location', 'Location verified from the SOS event.'],
                    ['called_patient', 'Patient contact attempt recorded.'],
                ];

                foreach (array_slice($actions, 0, 1 + ($index % 3)) as [$action, $detail]) {
                    SosResponseAction::updateOrCreate(
                        [
                            'sos_event_id' => $event->id,
                            'user_id' => $actor->id,
                            'action' => $action,
                        ],
                        [
                            'actor_name' => $actor->fullName(),
                            'detail' => $detail,
                        ],
                    );
                }
            },
        );
    }

    private function seedPendingInvitations(Carbon $now): void
    {
        User::query()
            ->where('approval_status', 'pending_approval')
            ->orderBy('id')
            ->get()
            ->each(function (User $user, int $index) use ($now): void {
                UserInvite::updateOrCreate(
                    ['user_id' => $user->id],
                    [
                        'token' => hash('sha256', 'mcare-demo-invite-'.$user->id),
                        'expires_at' => $now->copy()->addDays(3),
                        'accepted_at' => $index === 0 ? $now->copy()->subDay() : null,
                    ],
                );
            });
    }

    private function assignedDoctor(User $patient): ?User
    {
        $assignment = CareAssignment::query()
            ->with('provider.user')
            ->where('patient_user_id', $patient->id)
            ->whereNull('ended_at')
            ->orderByRaw("CASE WHEN role = 'Primary' THEN 0 ELSE 1 END")
            ->first();

        return $assignment?->provider?->user;
    }

    private function homeRoute(string $role): string
    {
        return match ($role) {
            'doctor' => '/doctor/dashboard',
            'admin' => '/admin/dashboard',
            'mcare_assistant' => '/assistant/dashboard',
            default => '/patient/dashboard',
        };
    }
}
