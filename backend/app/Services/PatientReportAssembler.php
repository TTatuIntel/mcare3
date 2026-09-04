<?php

namespace App\Services;

use App\Models\PatientReportRequest;
use App\Models\User;
use App\Support\PatientReportSections;
use Illuminate\Support\Carbon;

/**
 * Turns a consented, signed report request into the actual document body.
 *
 * Only the sections ticked on the request are ever produced — a section the
 * patient did not consent to is simply not assembled, rather than assembled
 * and filtered later. That keeps the confidentiality guarantee structural.
 *
 * Output is a list of blocks the client renders verbatim:
 *   ['key', 'title', 'kind' => 'fields'|'table'|'notes', ...payload]
 */
class PatientReportAssembler
{
    public function __construct(private readonly UserDossierService $dossiers) {}

    /**
     * @return array<string, mixed>
     */
    public function assemble(PatientReportRequest $request): array
    {
        /** @var User $patient */
        $patient = $request->patient()->firstOrFail();
        $dossier = $this->dossiers->build($patient);

        $blocks = [];
        foreach (($request->sections ?? []) as $key) {
            $block = $this->section($key, $dossier, $patient);
            if ($block !== null) {
                $blocks[] = $block;
            }
        }

        return [
            'title' => $request->title,
            'purpose' => $request->purpose,
            'recipient' => $request->recipient,
            'patient_name' => $patient->fullName(),
            'patient_unique_id' => $patient->unique_id,
            'generated_at' => now()->toIso8601String(),
            'prepared_by' => $request->requestedBy?->fullName(),
            'consent' => [
                'required' => (bool) $request->consent_required,
                'granted_at' => $request->consented_at?->toIso8601String(),
                'method' => $request->consent_method,
            ],
            'signature' => [
                'required' => (bool) $request->signature_required,
                'signed_at' => $request->signed_at?->toIso8601String(),
                'name' => $request->signature_name,
                'note' => $request->signature_note,
            ],
            'sections' => $blocks,
        ];
    }

    /**
     * @param  array<string, mixed>  $d
     * @return array<string, mixed>|null
     */
    private function section(string $key, array $d, User $patient): ?array
    {
        $clinical = $d['clinical'] ?? [];
        $health = $clinical['health'] ?? null;
        $title = PatientReportSections::label($key);

        return match ($key) {
            'identity' => $this->fields($key, $title, [
                'Full name' => $d['account']['name'],
                'Patient ID' => $d['account']['unique_id'],
                'Account status' => $this->titleCase($d['account']['status'] ?? ''),
                'Registered' => $this->date($d['account']['created_at'] ?? null),
            ]),

            'demographics' => $this->fields($key, $title, [
                'Date of birth' => $this->date($health['date_of_birth'] ?? null),
                'Age' => $this->age($health['date_of_birth'] ?? null),
                'Gender' => $this->titleCase($health['gender'] ?? ''),
                'Blood type' => $health['blood_type'] ?? null,
            ]),

            'contact' => $this->fields($key, $title, [
                'Email' => $d['account']['email'],
                'Phone' => $d['account']['phone'],
            ]),

            'address' => $this->fields($key, $title, [
                'Address' => $health['address'] ?? null,
                'Location sharing' => isset($health['location_consent'])
                    ? ($health['location_consent'] ? 'Consented' : 'Not consented')
                    : null,
            ]),

            'next_of_kin' => $this->table(
                $key,
                $title,
                ['Name', 'Relationship', 'Phone', 'Email'],
                array_map(fn (array $c) => [
                    $c['name'] ?? '',
                    $c['relationship'] ?? '',
                    $c['phone'] ?? '',
                    $c['email'] ?? '',
                ], $clinical['emergency_contacts'] ?? []),
            ),

            'account' => $this->fields($key, $title, [
                'Account opened' => $this->date($d['account']['created_at'] ?? null),
                'Email verified' => $this->date($d['account']['email_verified_at'] ?? null),
                'Approved' => $this->date($d['application']['approved_at'] ?? null),
                'Approved by' => $d['application']['approved_by_name'] ?? null,
                'Last sign-in' => $this->dateTime($d['security']['last_login_at'] ?? null),
                'Total sign-ins' => (string) ($d['security']['login_count'] ?? 0),
                'Sign-in method' => $this->authMethods($d['security'] ?? []),
                'Profile complete' => ($d['account']['profile_complete'] ?? false) ? 'Yes' : 'No',
            ]),

            'care_team' => $this->table(
                $key,
                $title,
                ['Provider', 'Specialty', 'Role', 'Assigned'],
                array_map(fn (array $a) => [
                    $a['provider_name'] ?? '',
                    $a['provider_specialty'] ?? '',
                    $this->titleCase($a['role'] ?? ''),
                    $this->date($a['assigned_at'] ?? null),
                ], $clinical['care_team'] ?? []),
            ),

            'health_profile' => $this->fields($key, $title, [
                'Height' => isset($health['height_cm']) ? $health['height_cm'].' cm' : null,
                'Weight' => isset($health['weight_kg']) ? $health['weight_kg'].' kg' : null,
                'BMI' => $this->bmi($health),
                'Chronic conditions' => $this->listOr($health['chronic_conditions'] ?? [], 'None recorded'),
                'Allergies' => ($health['no_known_allergies'] ?? false)
                    ? 'None known'
                    : $this->listOr($health['allergies'] ?? [], 'Not recorded'),
                'Current medications (self-reported)' => ($health['no_current_medications'] ?? false)
                    ? 'None'
                    : $this->listOr($health['current_medications'] ?? [], 'Not recorded'),
            ]),

            'vitals_summary' => $this->table(
                $key,
                $title,
                ['Vital', 'Latest', 'Risk', 'Recorded', 'Readings (30d)', 'Trend'],
                array_map(fn (array $v) => [
                    $v['label'] ?? $v['vital_key'],
                    $v['latest_value'] ?? '—',
                    $this->titleCase($v['latest_risk'] ?? ''),
                    $this->dateTime($v['latest_at'] ?? null),
                    (string) ($v['readings_30d'] ?? 0),
                    $this->titleCase($v['trend'] ?? ''),
                ], $clinical['vitals_summary'] ?? []),
            ),

            'vitals_readings' => $this->table(
                $key,
                $title,
                ['Recorded', 'Vital', 'Value', 'Risk', 'Note'],
                array_map(fn (array $r) => [
                    $this->dateTime($r['recorded_at'] ?? null),
                    $r['vital_key'] ?? '',
                    $r['display_value'] ?? '',
                    $this->titleCase($r['risk'] ?? ''),
                    $r['note'] ?? '',
                ], $clinical['recent_readings'] ?? []),
            ),

            'medications' => $this->table(
                $key,
                $title,
                ['Medication', 'Dosage', 'Frequency', 'Prescriber', 'Started', 'Status'],
                array_map(fn (array $m) => [
                    $m['name'] ?? '',
                    $m['dosage'] ?? '',
                    $m['frequency'] ?? '',
                    $m['prescribed_by_name'] ?? $m['prescribed_by'] ?? '',
                    $this->date($m['start_date'] ?? null),
                    ($m['active'] ?? false) ? 'Active' : 'Ended',
                ], $clinical['medications'] ?? []),
            ),

            'adherence' => $this->fields($key, $title, [
                'Adherence (30 days)' => ($d['progress']['adherence_percent'] ?? null) === null
                    ? 'No scheduled doses'
                    : $d['progress']['adherence_percent'].'%',
                'Doses due' => (string) ($d['progress']['doses_due_30d'] ?? 0),
                'Doses taken' => (string) ($d['progress']['doses_taken_30d'] ?? 0),
                'Doses missed' => (string) ($d['progress']['doses_missed_30d'] ?? 0),
            ]),

            'meal_plans' => $this->table(
                $key,
                $title,
                ['Meal', 'Type', 'Calories', 'Protein', 'Carbs', 'Fat', 'Assigned by', 'Date'],
                array_map(fn (array $m) => [
                    $m['title'] ?? '',
                    $this->titleCase($m['meal_type'] ?? ''),
                    (string) ($m['calories'] ?? ''),
                    (string) ($m['protein'] ?? ''),
                    (string) ($m['carbs'] ?? ''),
                    (string) ($m['fat'] ?? ''),
                    $m['assigned_by'] ?? '',
                    $this->date($m['assigned_at'] ?? null),
                ], $clinical['meal_plans'] ?? []),
            ),

            'appointments' => $this->table(
                $key,
                $title,
                ['Scheduled', 'Doctor', 'Type', 'Status', 'Reason'],
                array_map(fn (array $a) => [
                    $this->dateTime($a['scheduled_at'] ?? null),
                    $a['doctor_name'] ?? '',
                    $this->titleCase($a['type'] ?? ''),
                    $this->titleCase($a['status'] ?? ''),
                    $a['reason'] ?? '',
                ], $clinical['appointments'] ?? []),
            ),

            'alerts' => $this->table(
                $key,
                $title,
                ['Raised', 'Kind', 'Alert'],
                array_map(fn (array $a) => [
                    $this->dateTime($a['created_at'] ?? null),
                    $this->titleCase(str_replace('_', ' ', $a['kind'] ?? '')),
                    trim(($a['title'] ?? '').' — '.($a['body'] ?? ''), ' —'),
                ], $clinical['alerts'] ?? []),
            ),

            'sos' => $this->table(
                $key,
                $title,
                ['Triggered', 'Kind', 'Status', 'Location', 'Responder'],
                array_map(fn (array $s) => [
                    $this->dateTime($s['triggered_at'] ?? null),
                    $this->titleCase($s['kind'] ?? ''),
                    $this->titleCase($s['status'] ?? ''),
                    $s['location_label'] ?? '',
                    $s['responded_by'] ?? '',
                ], $clinical['sos_events'] ?? []),
            ),

            // Index only — the files themselves are never inlined into a report.
            'documents' => $this->table(
                $key,
                $title,
                ['Title', 'Category', 'Uploaded', 'Uploaded by'],
                array_map(fn (array $doc) => [
                    $doc['title'] ?? '',
                    $this->titleCase($doc['category'] ?? ''),
                    $this->date($doc['uploaded_at'] ?? null),
                    $doc['uploaded_by'] ?? '',
                ], $clinical['documents'] ?? []),
            ),

            'notes' => $this->notes(
                $key,
                $title,
                array_map(fn (array $r) => [
                    'title' => $r['title'] ?? '',
                    'author' => $r['author_name'] ?? '',
                    'at' => $this->date($r['created_at'] ?? null),
                    'body' => $r['body'] ?? '',
                ], array_values(array_filter(
                    $clinical['reports'] ?? [],
                    fn (array $r) => (bool) ($r['published'] ?? false),
                ))),
            ),

            'progress' => $this->fields($key, $title, [
                'Engagement score' => ($d['progress']['engagement_score'] ?? 0).'%',
                'Logging streak' => ($d['progress']['logging_streak_days'] ?? 0).' days',
                'Readings (7 days)' => (string) ($d['progress']['readings_7d'] ?? 0),
                'Readings (30 days)' => (string) ($d['progress']['readings_30d'] ?? 0),
                'Last reading' => $this->dateTime($d['progress']['last_reading_at'] ?? null),
                'Appointments kept' => (string) ($d['progress']['appointments_kept'] ?? 0),
                'Appointments missed' => (string) ($d['progress']['appointments_missed'] ?? 0),
            ]),

            default => null,
        };
    }

    // ------------------------------------------------------------------
    // block builders
    // ------------------------------------------------------------------

    /**
     * @param  array<string, string|null>  $fields
     * @return array<string, mixed>
     */
    private function fields(string $key, string $title, array $fields): array
    {
        $rows = [];
        foreach ($fields as $label => $value) {
            $rows[] = [
                'label' => $label,
                'value' => ($value === null || $value === '') ? 'Not recorded' : $value,
            ];
        }

        return ['key' => $key, 'title' => $title, 'kind' => 'fields', 'rows' => $rows];
    }

    /**
     * @param  list<string>  $columns
     * @param  list<list<string>>  $rows
     * @return array<string, mixed>
     */
    private function table(string $key, string $title, array $columns, array $rows): array
    {
        return [
            'key' => $key,
            'title' => $title,
            'kind' => 'table',
            'columns' => $columns,
            'rows' => array_values($rows),
            'empty_message' => 'Nothing recorded.',
        ];
    }

    /**
     * @param  list<array<string, string>>  $notes
     * @return array<string, mixed>
     */
    private function notes(string $key, string $title, array $notes): array
    {
        return [
            'key' => $key,
            'title' => $title,
            'kind' => 'notes',
            'notes' => array_values($notes),
            'empty_message' => 'No published notes.',
        ];
    }

    // ------------------------------------------------------------------
    // formatting
    // ------------------------------------------------------------------

    private function date(?string $iso): ?string
    {
        return $iso ? Carbon::parse($iso)->format('d M Y') : null;
    }

    private function dateTime(?string $iso): ?string
    {
        return $iso ? Carbon::parse($iso)->format('d M Y, H:i') : null;
    }

    private function age(?string $dob): ?string
    {
        return $dob ? Carbon::parse($dob)->age.' years' : null;
    }

    /**
     * @param  array<string, mixed>|null  $health
     */
    private function bmi(?array $health): ?string
    {
        $h = (float) ($health['height_cm'] ?? 0);
        $w = (float) ($health['weight_kg'] ?? 0);
        if ($h <= 0 || $w <= 0) {
            return null;
        }
        $bmi = $w / (($h / 100) ** 2);
        $band = $bmi < 18.5 ? 'Underweight'
            : ($bmi < 25 ? 'Healthy' : ($bmi < 30 ? 'Overweight' : 'Obese'));

        return number_format($bmi, 1).' ('.$band.')';
    }

    /**
     * @param  array<int, string>  $values
     */
    private function listOr(array $values, string $fallback): string
    {
        $values = array_values(array_filter($values));

        return $values === [] ? $fallback : implode(', ', $values);
    }

    /**
     * @param  array<string, mixed>  $security
     */
    private function authMethods(array $security): string
    {
        $methods = [];
        if ($security['has_password'] ?? false) {
            $methods[] = 'Password';
        }
        if ($security['google_linked'] ?? false) {
            $methods[] = 'Google';
        }
        if ($security['apple_linked'] ?? false) {
            $methods[] = 'Apple';
        }

        return $methods === [] ? 'Not recorded' : implode(' · ', $methods);
    }

    private function titleCase(string $value): string
    {
        return $value === '' ? '' : ucfirst(str_replace('_', ' ', $value));
    }
}
