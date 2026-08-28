<?php

namespace Database\Seeders;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\ChatMessage;
use App\Models\ClinicalReport;
use App\Models\Conversation;
use App\Models\Medication;
use App\Models\PatientAssignedVital;
use App\Models\PatientHealthProfile;
use App\Models\PatientTrackedVital;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Seeds the four additional patients assigned to Dr. Mensah and Dr. Adeyemi
 * so the doctor workspace has a realistic caseload with varied risk levels.
 *
 * Depends on StaffSeeder (doctors must exist first).
 */
class PatientCaseloadSeeder extends Seeder
{
    public function run(): void
    {
        $now = now();
        mt_srand(42);

        $mensah          = User::where('email', 'dr.mensah@mcare.health')->first();
        $adeyemi         = User::where('email', 'dr.adeyemi@mcare.health')->first();
        $mensahProvider  = $mensah  ? CareProvider::where('user_id', $mensah->id)->first()  : null;
        $adeyemiProvider = $adeyemi ? CareProvider::where('user_id', $adeyemi->id)->first() : null;

        // ── Brian Otieno — asthma, normal risk, Dr. Mensah ────────────────
        $brian = $this->upsertPatient(
            'brian.otieno@example.com',
            'MCR-001290',
            'Brian', 'Otieno',
            '+254 712 100 001',
            [
                'gender'             => 'male',
                'date_of_birth'      => '1984-06-22',
                'chronic_conditions' => ['Asthma'],
                'allergies'          => ['Dust mites'],
            ],
            ['respiratoryRate', 'bloodOxygen', 'heartRate'],
        );
        $this->assign($brian, $mensahProvider, 'Primary', $now->copy()->subDays(120));
        $this->seedVitalSeries($brian->id, 'respiratoryRate', 16, null, 3, days: 14, perDay: 1);
        $this->seedVitalSeries($brian->id, 'bloodOxygen',     97, null, 2, days: 14, perDay: 1);

        Appointment::updateOrCreate(
            ['user_id' => $brian->id, 'reason' => 'Asthma follow-up'],
            [
                'doctor_user_id'   => $mensah?->id,
                'doctor_name'      => 'Dr. Kojo Mensah',
                'doctor_specialty' => 'Internal medicine',
                'scheduled_at'     => $now->copy()->addHours(5),
                'duration_minutes' => 30,
                'type'             => 'inPerson',
                'status'           => 'scheduled',
                'location_or_link' => 'mCare Clinic, Room 2A',
            ],
        );

        // ── Wangari Njeri — post-stroke, critical risk, Dr. Adeyemi ───────
        $wangari = $this->upsertPatient(
            'wangari.njeri@example.com',
            'MCR-001291',
            'Wangari', 'Njeri',
            '+254 712 100 002',
            [
                'gender'             => 'female',
                'date_of_birth'      => '1958-11-03',
                'chronic_conditions' => ['Post-stroke recovery', 'Hypertension'],
                'allergies'          => [],
            ],
            ['bloodPressure', 'bloodOxygen', 'heartRate'],
        );
        $this->assign($wangari, $adeyemiProvider, 'Primary', $now->copy()->subDays(90));

        VitalReading::where('user_id', $wangari->id)->delete();
        VitalReading::create([
            'user_id'         => $wangari->id,
            'vital_key'       => 'bloodPressure',
            'value'           => 172,
            'secondary_value' => 108,
            'risk'            => 'critical',
            'recorded_at'     => $now->copy()->subMinutes(4),
        ]);
        VitalReading::create([
            'user_id'     => $wangari->id,
            'vital_key'   => 'bloodOxygen',
            'value'       => 88,
            'risk'        => 'critical',
            'recorded_at' => $now->copy()->subHours(2),
        ]);

        $this->upsertDoctorAlert(
            $wangari->id,
            'vital_critical',
            'Blood pressure critical',
            '172/108 mmHg — immediate review required.',
            false,
            $now->copy()->subMinutes(5),
        );
        $this->upsertDoctorAlert(
            $wangari->id,
            'vital_critical',
            'Blood oxygen low',
            '88 % SpO₂ — below safe threshold.',
            false,
            $now->copy()->subHours(2),
        );

        SosEvent::updateOrCreate(
            ['user_id' => $wangari->id, 'status' => 'active'],
            [
                'kind'           => 'medical',
                'location_label' => 'Karen, Nairobi',
                'note'           => 'Sudden weakness on left side.',
                'triggered_at'   => $now->copy()->subMinutes(8),
            ],
        );

        // ── Daniel Mwangi — wellness, normal risk, Dr. Mensah ─────────────
        $daniel = $this->upsertPatient(
            'daniel.mwangi@example.com',
            'MCR-001292',
            'Daniel', 'Mwangi',
            '+254 712 100 003',
            [
                'gender'             => 'male',
                'date_of_birth'      => '1992-01-18',
                'chronic_conditions' => [],
                'allergies'          => [],
                'no_known_allergies' => true,
            ],
            ['heartRate', 'weight'],
        );
        $this->assign($daniel, $mensahProvider, 'Primary', $now->copy()->subDays(30));
        $this->seedVitalSeries($daniel->id, 'heartRate', 72, null, 8, days: 7, perDay: 1);
        $this->seedVitalSeries($daniel->id, 'weight',    78, null, 1, days: 7, perDay: 1);

        // ── Esther Wambui — hypertension, warning risk, Dr. Mensah ────────
        $esther = $this->upsertPatient(
            'esther.wambui@example.com',
            'MCR-001293',
            'Esther', 'Wambui',
            '+254 712 100 004',
            [
                'gender'             => 'female',
                'date_of_birth'      => '1964-08-09',
                'chronic_conditions' => ['Hypertension'],
                'allergies'          => ['Sulfa drugs'],
            ],
            ['bloodPressure', 'heartRate'],
        );
        $this->assign($esther, $mensahProvider, 'Primary', $now->copy()->subDays(180));

        VitalReading::where('user_id', $esther->id)->delete();
        VitalReading::create([
            'user_id'         => $esther->id,
            'vital_key'       => 'bloodPressure',
            'value'           => 142,
            'secondary_value' => 92,
            'risk'            => 'warning',
            'recorded_at'     => $now->copy()->subHours(1),
        ]);
        VitalReading::create([
            'user_id'     => $esther->id,
            'vital_key'   => 'heartRate',
            'value'       => 112,
            'risk'        => 'warning',
            'recorded_at' => $now->copy()->subHours(1)->subMinutes(4),
        ]);

        $this->upsertDoctorAlert(
            $esther->id,
            'vital_warning',
            'Heart rate elevated',
            '112 bpm — above resting target.',
            false,
            $now->copy()->subHours(1)->subMinutes(4),
        );

        Medication::updateOrCreate(
            ['user_id' => $esther->id, 'name' => 'Amlodipine'],
            [
                'dosage'               => '5 mg',
                'frequency'            => 'Once daily',
                'form'                 => 'Tablet',
                'prescribed_by'        => 'Dr. Kojo Mensah',
                'prescribed_by_user_id'=> $mensah?->id,
                'start_date'           => $now->copy()->subDays(2),
                'active'               => true,
                'source'               => 'doctorPrescribed',
            ],
        );

        Appointment::updateOrCreate(
            ['user_id' => $esther->id, 'reason' => 'Medication check-in'],
            [
                'doctor_user_id'   => $mensah?->id,
                'doctor_name'      => 'Dr. Kojo Mensah',
                'scheduled_at'     => $now->copy()->addDay()->addHour(),
                'duration_minutes' => 20,
                'type'             => 'phone',
                'status'           => 'scheduled',
            ],
        );

        VitalReportRequest::updateOrCreate(
            ['user_id' => $esther->id, 'note' => 'Medication side-effect review'],
            [
                'range_from'        => $now->copy()->subDays(14),
                'range_to'          => $now,
                'vitals'            => ['bloodPressure', 'heartRate'],
                'status'            => 'pending',
                'current_responder' => 'doctor',
            ],
        );

        SosEvent::updateOrCreate(
            ['user_id' => $esther->id, 'status' => 'resolved', 'kind' => 'fall'],
            [
                'location_label' => 'Nairobi, Kilimani',
                'responded_by'   => 'Dr. Kojo Mensah',
                'triggered_at'   => $now->copy()->subDays(2),
                'responded_at'   => $now->copy()->subDays(2)->addMinutes(18),
            ],
        );

        if ($mensah) {
            $conv = Conversation::updateOrCreate(
                ['user_id' => $esther->id, 'participant_user_id' => $mensah->id],
                [
                    'participant_name'      => 'Dr. Kojo Mensah',
                    'participant_role'      => 'doctor',
                    'participant_specialty' => 'Internal medicine',
                ],
            );
            ChatMessage::updateOrCreate(
                ['conversation_id' => $conv->id, 'body' => 'Any dizziness since starting Amlodipine?'],
                [
                    'sender_user_id' => $mensah->id,
                    'read'           => true,
                    'sent_at'        => $now->copy()->subHours(3),
                ],
            );
        }

        ClinicalReport::updateOrCreate(
            ['patient_user_id' => $wangari->id, 'title' => 'Stroke recovery progress'],
            [
                'author_user_id' => $adeyemi?->id,
                'body'           => 'Mobility improving. Continue physio 3× weekly. Monitor BP closely.',
                'published'      => true,
                'published_at'   => $now->copy()->subDays(3),
            ],
        );
    }

    private function upsertPatient(
        string $email,
        string $uniqueId,
        string $first,
        string $last,
        string $phone,
        array $health,
        array $vitals,
    ): User {
        $user = User::updateOrCreate(
            ['email' => $email],
            [
                'unique_id'         => $uniqueId,
                'first_name'        => $first,
                'last_name'         => $last,
                'phone'             => $phone,
                'role'              => 'patient',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        PatientHealthProfile::updateOrCreate(
            ['user_id' => $user->id],
            array_merge([
                'blood_type'       => 'unknown',
                'height_cm'        => 170,
                'weight_kg'        => 70,
                'address'          => 'Nairobi, Kenya',
                'location_consent' => false,
            ], $health),
        );

        foreach ($vitals as $vital) {
            PatientAssignedVital::updateOrCreate(['user_id' => $user->id, 'vital_key' => $vital]);
            PatientTrackedVital::updateOrCreate(['user_id' => $user->id, 'vital_key' => $vital]);
        }

        return $user;
    }

    private function assign(User $patient, ?CareProvider $provider, string $role, \Carbon\Carbon $assignedAt): void
    {
        if (! $provider) return;
        CareAssignment::updateOrCreate(
            ['patient_user_id' => $patient->id, 'provider_id' => $provider->id, 'role' => $role],
            ['assigned_at' => $assignedAt, 'ended_at' => null],
        );
    }

    private function upsertDoctorAlert(int $patientUserId, string $kind, string $title, string $body, bool $read, \Carbon\Carbon $at): void
    {
        AppNotification::updateOrCreate(
            ['user_id' => $patientUserId, 'title' => $title],
            [
                'kind'       => $kind,
                'body'       => $body,
                'read'       => $read,
                'resolved'   => false,
                'created_at' => $at,
                'updated_at' => $at,
            ],
        );
    }

    private function seedVitalSeries(int $userId, string $key, float $base, ?float $secondaryBase, float $jitter, int $days = 14, int $perDay = 1): void
    {
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
                ]);
            }
        }
    }

    private function ranges(string $key): array
    {
        return match ($key) {
            'bloodPressure'   => [90, 120, 80, 140, 70, 160],
            'heartRate'       => [60, 100, 50, 120, 40, 140],
            'bloodOxygen'     => [95, 100, 90, 100, 85, 100],
            'respiratoryRate' => [12, 20, 10, 24, 8, 28],
            'weight'          => [0, 500, 0, 500, 0, 500],
            default           => [0, 100, 0, 100, 0, 100],
        };
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
