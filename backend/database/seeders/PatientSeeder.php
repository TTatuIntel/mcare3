<?php

namespace Database\Seeders;

use App\Models\Appointment;
use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\ChatMessage;
use App\Models\ClinicalReport;
use App\Models\Conversation;
use App\Models\EmergencyContact;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Models\PatientAssignedVital;
use App\Models\PatientHealthProfile;
use App\Models\PatientTrackedVital;
use App\Models\SosEvent;
use App\Models\SupportTicket;
use App\Models\SupportTicketReply;
use App\Models\User;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use App\Support\MedicalDocumentFiles;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Seeds the primary patient (Amara Okonkwo) with a complete clinical dataset:
 * vitals, medications, appointments, documents, messages, SOS events,
 * care team, support ticket, audit entries, and clinical report.
 *
 * Depends on StaffSeeder (doctors and assistant must exist first).
 */
class PatientSeeder extends Seeder
{
    public function run(): void
    {
        $doctor    = User::where('email', 'dr.mensah@mcare.health')->first();
        $doctor2   = User::where('email', 'dr.adeyemi@mcare.health')->first();
        $assistant = User::where('email', 'assistant@mcare.health')->first();

        // ── Patient: Amara Okonkwo ─────────────────────────────────────────
        $patient = User::updateOrCreate(
            ['email' => 'amara.okonkwo@example.com'],
            [
                'unique_id'         => 'MCR-001284',
                'first_name'        => 'Amara',
                'last_name'         => 'Okonkwo',
                'phone'             => '+254 712 000 000',
                'role'              => 'patient',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        PatientHealthProfile::updateOrCreate(
            ['user_id' => $patient->id],
            [
                'blood_type'             => 'oPos',
                'gender'                 => 'female',
                'date_of_birth'          => '1992-03-15',
                'height_cm'              => 165,
                'weight_kg'              => 68,
                'allergies'              => ['Penicillin'],
                'chronic_conditions'     => ['Type 2 diabetes', 'Hypertension'],
                'current_medications'    => ['Metformin 500mg', 'Lisinopril 10mg'],
                'address'                => 'Nairobi, Kenya',
                'location_consent'       => true,
                'no_known_allergies'     => false,
                'no_current_medications' => false,
            ],
        );

        EmergencyContact::updateOrCreate(
            ['user_id' => $patient->id, 'name' => 'David Okonkwo'],
            [
                'relationship' => 'Spouse',
                'phone'        => '+254 722 111 222',
                'email'        => 'david.okonkwo@example.com',
                'priority'     => 1,
            ],
        );

        EmergencyContact::updateOrCreate(
            ['user_id' => $patient->id, 'name' => 'Grace Okonkwo'],
            [
                'relationship' => 'Sister',
                'phone'        => '+254 733 444 555',
                'email'        => 'grace.okonkwo@example.com',
                'priority'     => 2,
            ],
        );

        foreach (['bloodPressure', 'bloodGlucose'] as $vital) {
            PatientAssignedVital::updateOrCreate(
                ['user_id' => $patient->id, 'vital_key' => $vital],
            );
        }

        foreach (['bloodPressure', 'bloodGlucose', 'heartRate', 'bloodOxygen'] as $vital) {
            PatientTrackedVital::updateOrCreate(
                ['user_id' => $patient->id, 'vital_key' => $vital],
            );
        }

        $now = now();
        mt_srand(42);

        // ── Vitals (30 days) ───────────────────────────────────────────────
        VitalReading::where('user_id', $patient->id)->delete();
        $this->seedVitalSeries($patient->id, 'bloodPressure', 118, 78,  16, perDay: 2);
        $this->seedVitalSeries($patient->id, 'heartRate',     76,  null, 18, perDay: 2);
        $this->seedVitalSeries($patient->id, 'bloodOxygen',   97,  null,  4, perDay: 1);
        $this->seedVitalSeries($patient->id, 'bloodGlucose',  102, null, 30, perDay: 3);

        // ── Medications ────────────────────────────────────────────────────
        Medication::where('user_id', $patient->id)->delete();
        $meds = [
            ['Metformin',    '500 mg',  'Twice daily',        'Tablet',  'Take with food',        'Dr. Kojo Mensah',   120, null, 2,    null],
            ['Lisinopril',   '10 mg',   'Once daily',         'Tablet',  'Take in the morning',   'Dr. Sarah Adeyemi',  90, null, 1,    10  ],
            ['Atorvastatin', '20 mg',   'Once daily at night','Tablet',  null,                    'Dr. Sarah Adeyemi',  60, null, 3,    null],
            ['Vitamin D3',   '1000 IU', 'Once daily',         'Capsule', null,                    'Self-added',         30, null, null, null],
        ];
        foreach ($meds as [$name, $dosage, $freq, $form, $instr, $by, $startAgo, $endAgo, $refills, $expiryFromNow]) {
            $med = Medication::create([
                'user_id'               => $patient->id,
                'name'                  => $name,
                'dosage'                => $dosage,
                'frequency'             => $freq,
                'form'                  => $form,
                'instructions'          => $instr,
                'prescribed_by'         => $by,
                'prescribed_by_user_id' => str_starts_with($by, 'Dr. Kojo')
                    ? $doctor?->id
                    : (str_starts_with($by, 'Dr. Sarah') ? $doctor2?->id : null),
                'start_date'            => $now->copy()->subDays($startAgo),
                'end_date'              => $endAgo ? $now->copy()->subDays($endAgo) : null,
                'expiry_date'           => $expiryFromNow ? $now->copy()->addDays($expiryFromNow) : null,
                'refills_left'          => $refills,
                'source'                => $by === 'Self-added' ? 'patientAdded' : 'doctorPrescribed',
                'active'                => true,
            ]);

            $doses = str_contains($freq, 'Twice') ? 2 : 1;
            for ($i = 0; $i < $doses; $i++) {
                $hour = $i === 0 ? 8 : 20;
                MedicationDose::create([
                    'medication_id' => $med->id,
                    'user_id'       => $patient->id,
                    'scheduled_at'  => $now->copy()->startOfDay()->addHours($hour),
                    'status'        => $now->hour > $hour ? 'taken' : 'pending',
                    'taken_at'      => $now->hour > $hour
                        ? $now->copy()->startOfDay()->addHours($hour)
                        : null,
                ]);
            }
        }

        // ── Appointments ───────────────────────────────────────────────────
        Appointment::where('user_id', $patient->id)->delete();
        Appointment::create([
            'user_id'          => $patient->id,
            'doctor_user_id'   => $doctor?->id,
            'doctor_name'      => 'Dr. Kojo Mensah',
            'doctor_specialty' => 'Internal medicine',
            'scheduled_at'     => $now->copy()->addDays(1)->setTime(15, 0),
            'duration_minutes' => 30,
            'type'             => 'virtual',
            'status'           => 'confirmed',
            'reason'           => 'Quarterly diabetes review',
            'location_or_link' => 'https://meet.mcare.health/a1',
        ]);
        Appointment::create([
            'user_id'          => $patient->id,
            'doctor_user_id'   => $doctor2?->id,
            'doctor_name'      => 'Dr. Sarah Adeyemi',
            'doctor_specialty' => 'Endocrinology',
            'scheduled_at'     => $now->copy()->addDays(7)->setTime(10, 30),
            'duration_minutes' => 45,
            'type'             => 'inPerson',
            'status'           => 'scheduled',
            'reason'           => 'In-person blood-work review',
            'location_or_link' => 'Nairobi Hospital, Suite 412',
        ]);

        // ── Documents ──────────────────────────────────────────────────────
        MedicalDocument::where('user_id', $patient->id)->delete();
        $lipid = MedicalDocumentFiles::storeFixtureCopy($patient->id, 'Lipid panel — Jan 2026', 'pdf');
        MedicalDocument::create([
            'user_id'               => $patient->id,
            'title'                 => 'Lipid panel — Jan 2026',
            'category'              => 'labResult',
            'file_type'             => 'pdf',
            'storage_path'          => $lipid['path'],
            'size_bytes'            => $lipid['size'],
            'uploaded_by'           => 'Dr. Sarah Adeyemi',
            'description'           => 'Cholesterol panel, LDL within range.',
            'shared_with_doctor_id' => $doctor?->id,
            'uploaded_at'           => $now->copy()->subDays(8),
        ]);
        $xray = MedicalDocumentFiles::storeFixtureCopy($patient->id, 'Chest X-ray report', 'pdf');
        MedicalDocument::create([
            'user_id'      => $patient->id,
            'title'        => 'Chest X-ray report',
            'category'     => 'imaging',
            'file_type'    => 'pdf',
            'storage_path' => $xray['path'],
            'size_bytes'   => $xray['size'],
            'uploaded_by'  => 'Aga Khan Imaging',
            'uploaded_at'  => $now->copy()->subDays(20),
        ]);

        // ── Conversation ───────────────────────────────────────────────────
        Conversation::where('user_id', $patient->id)->delete();
        $conv = Conversation::create([
            'user_id'               => $patient->id,
            'participant_user_id'   => $doctor?->id,
            'participant_name'      => 'Dr. Kojo Mensah',
            'participant_role'      => 'doctor',
            'participant_specialty' => 'Internal medicine',
        ]);
        ChatMessage::create([
            'conversation_id' => $conv->id,
            'sender_user_id'  => $doctor?->id,
            'body'            => "Please share this week's glucose readings before our visit.",
            'read'            => false,
            'sent_at'         => $now->copy()->subHours(2),
        ]);
        ChatMessage::create([
            'conversation_id' => $conv->id,
            'sender_user_id'  => $patient->id,
            'body'            => 'Will do — uploading after lunch.',
            'read'            => true,
            'sent_at'         => $now->copy()->subMinutes(95),
        ]);

        // ── Notifications ──────────────────────────────────────────────────
        AppNotification::where('user_id', $patient->id)->delete();
        $notifications = [
            ['vital_warning', 'Blood glucose is high',      '168 mg/dL recorded at 8:12 AM — above your target range.',  false, $now->copy()->subMinutes(14)],
            ['appointment',   'Appointment tomorrow',        'Dr. Mensah at 3:00 PM — virtual visit.',                    false, $now->copy()->subHours(3)  ],
            ['medication',    'Time for Metformin',          '500 mg with breakfast.',                                     true,  $now->copy()->subHours(6)  ],
            ['message',       'New message from Dr. Mensah', "Please share this week's glucose readings before our visit.", true, $now->copy()->subDays(1)  ],
        ];
        foreach ($notifications as [$kind, $title, $body, $read, $at]) {
            AppNotification::create([
                'user_id'    => $patient->id,
                'kind'       => $kind,
                'title'      => $title,
                'body'       => $body,
                'read'       => $read,
                'resolved'   => false,
                'created_at' => $at,
                'updated_at' => $at,
            ]);
        }

        // ── Support Ticket ─────────────────────────────────────────────────
        SupportTicket::where('user_id', $patient->id)->delete();
        $ticket = SupportTicket::create([
            'user_id'        => $patient->id,
            'subject'        => 'Cannot upload PDF documents',
            'description'    => 'When I tap upload nothing happens on iOS.',
            'category'       => 'technical',
            'priority'       => 'normal',
            'status'         => 'open',
            'updated_at_app' => $now->copy()->subDays(1),
        ]);
        SupportTicketReply::create([
            'ticket_id' => $ticket->id,
            'author'    => 'Amara Okonkwo',
            'is_staff'  => false,
            'body'      => "Hi team, the upload button doesn't respond.",
            'sent_at'   => $now->copy()->subDays(1),
        ]);
        SupportTicketReply::create([
            'ticket_id'      => $ticket->id,
            'author_user_id' => $assistant?->id,
            'author'         => 'mCare Support',
            'is_staff'       => true,
            'body'           => 'Thanks Amara — we are reproducing this now.',
            'sent_at'        => $now->copy()->subHours(20),
        ]);

        // ── SOS History ────────────────────────────────────────────────────
        SosEvent::where('user_id', $patient->id)->delete();
        SosEvent::create([
            'user_id'        => $patient->id,
            'kind'           => 'medical',
            'status'         => 'active',
            'location_label' => 'Nairobi, Westlands',
            'latitude'       => -1.2674,
            'longitude'      => 36.8070,
            'note'           => 'Patient reports chest tightness.',
            'triggered_at'   => $now->copy()->subMinutes(12),
        ]);
        SosEvent::create([
            'user_id'        => $patient->id,
            'kind'           => 'medical',
            'status'         => 'resolved',
            'location_label' => 'Westlands, Nairobi',
            'note'           => 'Felt dizzy after work; resolved on its own.',
            'responded_by'   => 'Dr. Kojo Mensah',
            'triggered_at'   => $now->copy()->subDays(12)->setTime(18, 22),
            'responded_at'   => $now->copy()->subDays(12)->setTime(18, 24),
        ]);

        // ── Care Team ──────────────────────────────────────────────────────
        $mensahProvider  = CareProvider::where('name', 'Dr. Kojo Mensah')->first();
        $adeyemiProvider = CareProvider::where('name', 'Dr. Sarah Adeyemi')->first();
        if ($mensahProvider) {
            CareAssignment::updateOrCreate(
                ['patient_user_id' => $patient->id, 'provider_id' => $mensahProvider->id, 'role' => 'Primary'],
                ['assigned_at' => $now->copy()->subDays(210)],
            );
        }
        if ($adeyemiProvider) {
            CareRequest::updateOrCreate(
                ['user_id' => $patient->id, 'provider_id' => $adeyemiProvider->id],
                [
                    'provider_name'      => 'Dr. Sarah Adeyemi',
                    'provider_specialty' => 'Endocrinology',
                    'reason'             => 'Specialist diabetes review',
                    'status'             => 'approved',
                ],
            );
        }

        // ── Vital Report Request ───────────────────────────────────────────
        VitalReportRequest::where('user_id', $patient->id)->delete();
        VitalReportRequest::create([
            'user_id'           => $patient->id,
            'range_from'        => $now->copy()->subDays(45),
            'range_to'          => $now->copy()->subDays(15),
            'vitals'            => ['bloodPressure', 'bloodGlucose', 'heartRate'],
            'note'              => 'For cardiology follow-up',
            'status'            => 'pending',
            'current_responder' => 'mcareAssistant',
            'last_escalated_at' => $now->copy()->subDays(1),
        ]);

        // ── Audit Trail ────────────────────────────────────────────────────
        AuditEntry::create([
            'actor_user_id' => $doctor?->id,
            'actor_label'   => 'Dr. Kojo Mensah',
            'action'        => 'Issued prescription',
            'target'        => 'Amara Okonkwo — Lisinopril 10mg',
            'category'      => 'activity',
            'happened_at'   => $now->copy()->subDays(1),
        ]);
        AuditEntry::create([
            'actor_label' => 'System',
            'action'      => 'Critical alert escalated',
            'target'      => 'Wangari Njeri — BP 172/108',
            'category'    => 'security',
            'happened_at' => $now->copy()->subHours(7),
        ]);

        // ── Clinical Report ────────────────────────────────────────────────
        ClinicalReport::create([
            'patient_user_id' => $patient->id,
            'author_user_id'  => $doctor?->id,
            'title'           => 'Quarterly diabetes review',
            'body'            => 'Glucose trend trending downward over 30 days. Adherence to Metformin 89%. Recommend continuing therapy.',
            'published'       => true,
            'published_at'    => $now->copy()->subDays(4),
        ]);
    }

    private function seedVitalSeries(
        int $userId,
        string $key,
        float $base,
        ?float $secondaryBase,
        float $jitter,
        int $days = 30,
        int $perDay = 2,
    ): void {
        $now    = now();
        $ranges = $this->ranges($key);
        for ($d = 0; $d < $days; $d++) {
            for ($i = 0; $i < $perDay; $i++) {
                $value     = $base + (mt_rand(-1000, 1000) / 1000) * $jitter;
                $secondary = $secondaryBase === null
                    ? null
                    : $secondaryBase + (mt_rand(-1000, 1000) / 1000) * ($jitter / 2);
                VitalReading::create([
                    'user_id'         => $userId,
                    'vital_key'       => $key,
                    'value'           => round($value, 1),
                    'secondary_value' => $secondary !== null ? round($secondary, 1) : null,
                    'risk'            => $this->assess($value, $ranges),
                    'recorded_at'     => $now->copy()
                        ->subDays($d)
                        ->subHours($i * 12)
                        ->subMinutes(mt_rand(0, 59)),
                    'note'            => null,
                ]);
            }
        }
    }

    private function ranges(string $key): array
    {
        return [
            'bloodPressure'   => [90, 120, 80, 140, 70, 160],
            'heartRate'       => [60, 100, 50, 120, 40, 140],
            'bloodOxygen'     => [95, 100, 90, 100, 85, 100],
            'bloodGlucose'    => [70, 100, 54, 126, 50, 180],
            'temperature'     => [36.1, 37.2, 35.5, 38.0, 35.0, 39.0],
            'respiratoryRate' => [12, 20, 10, 24, 8, 28],
            'weight'          => [0, 500, 0, 500, 0, 500],
        ][$key];
    }

    private function assess(float $v, array $r): string
    {
        [$nMin, $nMax, $wLow, $wHigh, $cLow, $cHigh] = $r;
        if ($v < $cLow || $v > $cHigh) return 'critical';
        if ($v < $wLow || $v > $wHigh) return 'warning';
        if ($v < $nMin || $v > $nMax)  return 'warning';
        return 'normal';
    }
}
