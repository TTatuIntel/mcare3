<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\ExternalAccessToken;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use App\Services\VitalAlertNotifier;
use App\Support\ApiResponse;
use App\Support\MedicalDocumentFiles;
use App\Support\VitalRisk;
use Illuminate\Http\Request;

/**
 * Token-scoped portal for external consulting physicians.
 *
 * Access is granted via a patient-generated time-limited token (long URL
 * token, or a short spoken access code exchanged for the token via
 * [resolveCode]). External doctors can review the patient summary and update
 * the record with findings: consultation notes, vital readings, prescriptions,
 * and uploaded documents/reports.
 */
class ExternalDoctorController extends Controller
{
    use ApiResponse;

    /**
     * Exchange a short spoken access code (e.g. "AB2D-9XKM") for the portal
     * token. Heavily rate-limited at the route level.
     */
    public function resolveCode(Request $request)
    {
        $data = $request->validate([
            'code' => 'required|string|min:6|max:16',
        ]);

        $code = strtoupper(trim($data['code']));
        // Accept the code with or without the dash.
        $normalized = str_replace('-', '', $code);
        if (strlen($normalized) === 8) {
            $code = substr($normalized, 0, 4).'-'.substr($normalized, 4);
        }

        $access = ExternalAccessToken::query()
            ->where('access_code', $code)
            ->first();

        if (! $access || ! $access->isValid()) {
            return $this->error('This access code is invalid or has expired.', 404);
        }

        return $this->success(['token' => $access->token]);
    }

    public function show(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()
            ->where('token', $token)
            ->with('patient.healthProfile')
            ->first();

        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $patient = $access->patient;
        if (! $patient || $patient->role !== 'patient') {
            return $this->error('Patient record not found.', 404);
        }

        $health = $patient->healthProfile;

        $latestReadings = VitalReading::where('user_id', $patient->id)
            ->orderByDesc('recorded_at')
            ->limit(20)
            ->get()
            ->map(fn (VitalReading $r) => array_merge($r->toApiArray(), [
                'risk' => $r->risk ?? 'unknown',
            ]));

        $catalog = VitalCatalog::where('enabled', true)
            ->get()
            ->map(fn (VitalCatalog $v) => [
                'vital_key' => $v->vital_key,
                'label' => $v->label ?? $v->vital_key,
                'unit' => $v->unit ?? '',
            ]);

        $medications = Medication::where('user_id', $patient->id)
            ->where('active', true)
            ->orderByDesc('created_at')
            ->limit(40)
            ->get()
            ->map(fn (Medication $m) => $m->toApiArray());

        $documents = MedicalDocument::where('user_id', $patient->id)
            ->orderByDesc('uploaded_at')
            ->limit(20)
            ->get()
            ->map(fn (MedicalDocument $d) => $d->toApiArray());

        return $this->success([
            'token' => $token,
            'expires_at' => $access->expires_at->toIso8601String(),
            // Also identifies the token-scoped pulse cursor. The client only
            // attempts a socket when public runtime config advertises one.
            'realtime_channel' => 'private-external.'.$access->id,
            'catalog' => $catalog,
            'patient' => [
                'id' => (string) $patient->id,
                'name' => $patient->fullName(),
                'unique_id' => $patient->unique_id,
                'age' => optional($health)->date_of_birth
                    ? \Carbon\Carbon::parse($health->date_of_birth)->age
                    : null,
                'sex' => optional($health)->gender,
                'blood_type' => optional($health)->blood_type,
                'condition' => is_array(optional($health)->chronic_conditions)
                    ? implode(' · ', $health->chronic_conditions)
                    : '',
                'allergies' => optional($health)->no_known_allergies
                    ? []
                    : (optional($health)->allergies ?? []),
                'no_known_allergies' => (bool) optional($health)->no_known_allergies,
            ],
            'vitals' => $latestReadings,
            'medications' => $medications,
            'documents' => $documents,
        ]);
    }

    public function addNote(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()->where('token', $token)->first();
        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $data = $request->validate([
            'note' => 'required|string|min:4|max:1000',
            'doctor_name' => 'nullable|string|max:120',
        ]);

        $author = $this->authorLabel($data['doctor_name'] ?? null);

        \App\Models\AuditEntry::create([
            'actor_user_id' => null,
            'actor_label' => $author,
            'action' => 'external.consultation_note',
            'target' => $access->patient?->fullName() ?? 'Patient',
            'category' => 'activity',
            'meta' => ['note' => $data['note'], 'token_id' => $access->id],
            'happened_at' => now(),
        ]);

        if ($access->patient) {
            AppNotification::create([
                'user_id' => $access->patient->id,
                'kind' => 'report',
                'title' => 'External consultation note added',
                'body' => $author.': '.\Illuminate\Support\Str::limit($data['note'], 180),
                'action_route' => '/patient/notifications',
                'read' => false,
            ]);
        }

        return $this->success(null, 'Consultation note recorded.');
    }

    /**
     * Record a vital reading observed by the external doctor (e.g. during an
     * emergency). Runs the same risk assessment + care-team alerting as a
     * patient-submitted reading, so critical findings escalate in real time.
     */
    public function addVital(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()
            ->where('token', $token)
            ->with('patient')
            ->first();
        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $patient = $access->patient;
        if (! $patient || $patient->role !== 'patient') {
            return $this->error('Patient record not found.', 404);
        }

        $data = $request->validate([
            'vital_key' => 'required|string|max:32',
            'value' => 'required|numeric',
            'secondary_value' => 'nullable|numeric',
            'note' => 'nullable|string|max:500',
            'doctor_name' => 'nullable|string|max:120',
        ]);

        if (! VitalCatalog::where('vital_key', $data['vital_key'])->exists()) {
            return $this->error('Unknown vital type.', 422);
        }

        $range = $patient->vitalRangeOverrides()
            ->where('vital_key', $data['vital_key'])
            ->first()
            ?? VitalCatalog::where('vital_key', $data['vital_key'])->first();

        $risk = $range ? VitalRisk::assess((float) $data['value'], $range) : 'unknown';

        $author = $this->authorLabel($data['doctor_name'] ?? null);

        $reading = $patient->vitalReadings()->create([
            'vital_key' => $data['vital_key'],
            'value' => $data['value'],
            'secondary_value' => $data['secondary_value'] ?? null,
            'recorded_at' => now(),
            'note' => trim(($data['note'] ?? '')."\nRecorded by {$author} via external portal."),
            'risk' => $risk,
        ]);

        VitalAlertNotifier::notify($patient, $reading);

        \App\Models\AuditEntry::create([
            'actor_user_id' => null,
            'actor_label' => $author,
            'action' => 'external.vital_recorded',
            'target' => $patient->fullName(),
            'category' => 'activity',
            'meta' => [
                'token_id' => $access->id,
                'vital_key' => $data['vital_key'],
                'value' => $data['value'],
                'risk' => $risk,
            ],
            'happened_at' => now(),
        ]);

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'vitalAlert',
            'title' => 'Vital recorded by external doctor',
            'body' => $author.' recorded a '.$data['vital_key'].' reading ('.$data['value'].').',
            'action_route' => '/patient/vitals',
            'action_arguments' => ['vital_key' => $data['vital_key']],
            'read' => false,
        ]);

        return $this->success([
            'vital' => array_merge($reading->toApiArray(), ['risk' => $risk]),
        ], 'Vital recorded.', 201);
    }

    /**
     * Assign a medication / prescription from the external portal.
     */
    public function addMedication(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()
            ->where('token', $token)
            ->with('patient')
            ->first();
        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $patient = $access->patient;
        if (! $patient || $patient->role !== 'patient') {
            return $this->error('Patient record not found.', 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:160',
            'dosage' => 'required|string|max:60',
            'frequency' => 'required|string|max:120',
            'form' => 'nullable|string|max:60',
            'instructions' => 'nullable|string|max:1000',
            'start_date' => 'nullable|date',
            'end_date' => 'nullable|date|after_or_equal:start_date',
            'doctor_name' => 'nullable|string|max:120',
        ]);

        $author = $this->authorLabel($data['doctor_name'] ?? null);

        $med = Medication::create([
            'user_id' => $patient->id,
            'name' => $data['name'],
            'dosage' => $data['dosage'],
            'frequency' => $data['frequency'],
            'form' => $data['form'] ?? null,
            'instructions' => $data['instructions'] ?? null,
            'prescribed_by' => $author,
            'prescribed_by_user_id' => null,
            'start_date' => $data['start_date'] ?? now()->toDateString(),
            'end_date' => $data['end_date'] ?? null,
            'refills_left' => 0,
            'source' => 'doctorPrescribed',
            'active' => true,
        ]);

        \App\Models\AuditEntry::create([
            'actor_user_id' => null,
            'actor_label' => $author,
            'action' => 'external.medication_assigned',
            'target' => $patient->fullName(),
            'category' => 'activity',
            'meta' => [
                'token_id' => $access->id,
                'medication_id' => $med->id,
                'name' => $med->name,
                'dosage' => $med->dosage,
            ],
            'happened_at' => now(),
        ]);

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'medication',
            'title' => 'Medication assigned by external doctor',
            'body' => "{$author} prescribed {$med->name} {$med->dosage}.",
            'action_route' => '/patient/medications',
            'read' => false,
        ]);

        return $this->success([
            'medication' => $med->toApiArray(),
        ], 'Medication assigned.', 201);
    }

    /**
     * Upload a document or clinical report to the patient's chart.
     */
    public function uploadDocument(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()
            ->where('token', $token)
            ->with('patient')
            ->first();
        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $patient = $access->patient;
        if (! $patient || $patient->role !== 'patient') {
            return $this->error('Patient record not found.', 404);
        }

        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $doctorName = $request->input('doctor_name');
        $author = $this->authorLabel(is_string($doctorName) ? $doctorName : null);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $patient->id);

        $doc = $patient->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'shared_with_doctor_id' => null,
            'uploaded_by' => $author,
            'uploaded_at' => now(),
        ]);

        \App\Models\AuditEntry::create([
            'actor_user_id' => null,
            'actor_label' => $author,
            'action' => 'external.document_uploaded',
            'target' => $patient->fullName(),
            'category' => 'activity',
            'meta' => [
                'token_id' => $access->id,
                'document_id' => $doc->id,
                'title' => $doc->title,
                'category' => $doc->category,
            ],
            'happened_at' => now(),
        ]);

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'report',
            'title' => 'Document uploaded by external doctor',
            'body' => "{$author} uploaded \"{$doc->title}\".",
            'action_route' => '/patient/documents',
            'read' => false,
        ]);

        return $this->success([
            'document' => $doc->toApiArray(),
        ], 'Document uploaded.', 201);
    }

    private function authorLabel(?string $doctorName): string
    {
        $name = trim((string) $doctorName);

        return $name !== '' ? 'External doctor '.$name : 'External doctor';
    }
}
