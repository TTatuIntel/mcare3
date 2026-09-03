<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\ClinicalReport;
use App\Models\Medication;
use App\Models\MedicalDocument;
use App\Models\PatientHealthProfile;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use App\Services\AuditService;
use Illuminate\Support\Facades\DB;
use App\Support\ApiResponse;
use App\Support\DocumentDelivery;
use App\Support\DocumentRemoval;
use App\Support\MedicalDocumentFiles;
use App\Support\VitalRecorder;
use App\Support\VitalAlertPayload;
use Illuminate\Http\Request;

/**
 * Per-patient detail view for the doctor workspace screen.
 *
 * Always gate via DoctorAccess::assertCaseload — never trust the
 * URL-bound patient model alone.
 */
class DoctorPatientController extends Controller
{
    use ApiResponse;

    /**
     * Honouring a patient's removal request is the one write here that deletes
     * something, so it records through the full audit service rather than
     * {@see DoctorAccess::audit()} — that helper writes no meta, and the whole
     * point of the entry is to outlive the row it describes.
     */
    public function __construct(private readonly AuditService $audit) {}

    public function show(Request $request, User $patient)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);

        $patient->load(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        return $this->success([
            'patient' => [
                'id' => (string) $patient->id,
                'unique_id' => $patient->unique_id,
                'name' => $patient->fullName(),
                'email' => $patient->email,
                'phone' => $patient->phone,
                'health' => optional($patient->healthProfile)->toApiArray(),
                'emergency_contacts' => $patient->emergencyContacts
                    ->map->toApiArray()
                    ->all(),
            ],

            'vitals' => VitalReading::where('user_id', $patient->id)
                ->orderByDesc('recorded_at')
                ->limit(500)
                ->get()
                ->map->toApiArray()
                ->all(),

            'medications' => Medication::where('user_id', $patient->id)
                ->orderByDesc('start_date')
                ->get()
                ->map->toApiArray()
                ->all(),

            'documents' => MedicalDocument::where('user_id', $patient->id)
                ->orderByDesc('uploaded_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'appointments' => Appointment::where('user_id', $patient->id)
                ->orderBy('scheduled_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'sos_events' => SosEvent::where('user_id', $patient->id)
                ->orderByDesc('triggered_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'vital_report_requests' => VitalReportRequest::where('user_id', $patient->id)
                ->orderByDesc('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'reports' => ClinicalReport::where('patient_user_id', $patient->id)
                ->orderByDesc('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),

            'alerts' => AppNotification::where('user_id', $patient->id)
                ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
                ->orderByDesc('created_at')
                ->limit(50)
                ->get()
                ->map(fn (AppNotification $n) => VitalAlertPayload::alertToApiArray($n, [
                    'patient_id' => (string) $patient->id,
                    'patient_name' => $patient->fullName(),
                ]))
                ->all(),

            'assigned_vitals' => $patient->assignedVitals
                ->pluck('vital_key')
                ->values()
                ->all(),
        ]);
    }

    /**
     * Assign or de-assign vital types the patient must track.
     * Only vitals present in the catalog are accepted.
     */
    public function updateAssignedVitals(Request $request, User $patient)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);

        $data = $request->validate([
            'assigned_vitals' => 'required|array|min:1',
            'assigned_vitals.*' => 'string',
        ]);

        $allowed = VitalCatalog::whereIn('vital_key', VitalCatalog::BUILTIN_KEYS)
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
            $actorLabel = 'Dr. '.$actor->fullName();
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

            DoctorAccess::audit(
                $actor,
                'Updated assigned vitals for '.$patient->fullName(),
                implode(', ', $keys),
            );
        }

        return $this->success([
            'assigned_vitals' => $keys,
        ], 'Assigned vitals updated.');
    }

    /**
     * Clinician chart edit — partial update of the patient's health profile.
     * Mirrors PatientProfileController::updateHealth but is callable by the
     * patient's assigned doctor, writes an AuditEntry, and posts a profile
     * notification to the patient.
     */
    public function updateChart(Request $request, User $patient)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);

        $data = $request->validate([
            'blood_type' => 'nullable|string|max:5',
            'gender' => 'nullable|string|max:20',
            'date_of_birth' => 'nullable|date',
            'height_cm' => 'nullable|numeric|min:1',
            'weight_kg' => 'nullable|numeric|min:1',
            'allergies' => 'nullable|array',
            'chronic_conditions' => 'nullable|array',
            'current_medications' => 'nullable|array',
            'address' => 'nullable|string|max:500',
            'location_consent' => 'nullable|boolean',
            'no_known_allergies' => 'nullable|boolean',
            'no_current_medications' => 'nullable|boolean',
            'note' => 'nullable|string|max:500',
        ]);

        $note = $data['note'] ?? null;
        unset($data['note']);

        // Only the fields the client actually sent.
        $updates = collect($data)->filter(fn ($v) => $v !== null)->all();
        if (empty($updates)) {
            return $this->error('No chart changes supplied.', 422);
        }

        $profile = $patient->healthProfile
            ?? PatientHealthProfile::create(['user_id' => $patient->id]);

        $before = $profile->only(array_keys($updates));
        $profile->update($updates);

        $changedLabels = [];
        foreach ($updates as $key => $value) {
            if (($before[$key] ?? null) != $value) {
                $changedLabels[] = self::labelFor($key);
            }
        }
        if (empty($changedLabels)) {
            return $this->success([
                'health' => $profile->fresh()->toApiArray(),
            ], 'No changes.');
        }

        $summary = implode(', ', $changedLabels);
        $actor = $request->user();
        $actorLabel = 'Dr. '.$actor->fullName();

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'profile',
            'title' => 'Chart updated by '.$actorLabel,
            'body' => $actorLabel.' updated your chart: '.$summary
                .($note !== null ? "\nNote: ".$note : ''),
            'action_route' => '/patient/profile',
            'read' => false,
        ]);

        DoctorAccess::audit(
            $actor,
            'Updated chart: '.$summary,
            $patient->fullName(),
        );

        return $this->success([
            'health' => $profile->fresh()->toApiArray(),
            'changes' => $changedLabels,
        ], 'Chart updated.');
    }

    public function storeDocument(Request $request, User $patient)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);

        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $patient->id);

        $doc = $patient->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'uploaded_by' => 'Dr. '.$request->user()->fullName(),
            'uploaded_at' => now(),
            // Part of the clinical record from the moment it is filed, so it
            // cannot later be deleted by staff or by the patient.
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        DoctorAccess::audit(
            $request->user(),
            'Uploaded document',
            $doc->title.' for '.$patient->fullName(),
        );

        // Filing the document is not the same as delivering it. Without this
        // the patient had to notice the new row on their own.
        DocumentDelivery::notifyOwner($doc, 'Dr. '.$request->user()->fullName());

        return $this->success(['document' => $doc->toApiArray()], 'Document uploaded.', 201);
    }

    public function updateDocument(Request $request, User $patient, MedicalDocument $document)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);
        abort_unless($document->user_id === $patient->id, 404);

        $data = MedicalDocumentFiles::validateUpdate($request);
        MedicalDocumentFiles::applyUpdate($document, $data, $request, $patient->id);

        DoctorAccess::audit(
            $request->user(),
            'Updated document',
            $document->title.' for '.$patient->fullName(),
        );

        return $this->success(['document' => $document->fresh()->toApiArray()], 'Document updated.');
    }

    /**
     * Delete a document — only where the patient has asked for it.
     *
     * Clinicians used to be able to delete anything in a patient's documents,
     * including the patient's own uploads and issued reports. Nothing in the
     * record disappears on one clinician's say-so: a document that is wrong is
     * corrected or superseded, and a report that should not have gone out is
     * revoked — both leave a trace, which deletion does not.
     *
     * What the flat refusal missed is that the patient can say so. A result
     * filed against the wrong person is theirs to have taken out, and once they
     * have asked, honouring it is the correct answer rather than an exception
     * to be worked around. The authority is the request, not the role, so this
     * is the same check and the same audit trail the admin route uses.
     */
    public function destroyDocument(Request $request, User $patient, MedicalDocument $document)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);
        abort_unless($document->user_id === $patient->id, 404);

        if (! $document->isRemovableByStaff()) {
            return $this->error(
                'Documents in the patient record cannot be deleted. Upload a '
                .'corrected version, ask mCare staff to revoke an issued '
                .'report, or ask the patient to request its removal.',
                403,
            );
        }

        DocumentRemoval::honour(
            $this->audit,
            $request->user(),
            $document,
            $request->string('note')->trim()->value() ?: null,
        );

        return $this->success(null, 'Document removed at the patient\'s request.');
    }

    /** Refuse a removal the patient asked for, with a reason they read. */
    public function declineDocumentRemoval(Request $request, User $patient, MedicalDocument $document)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);
        abort_unless($document->user_id === $patient->id, 404);

        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if (! $document->removalPending()) {
            return $this->error('There is no removal request to answer.', 422);
        }

        DocumentRemoval::decline(
            $this->audit,
            $request->user(),
            $document,
            trim($data['reason']),
        );

        return $this->success(
            ['document' => $document->fresh()->toApiArray()],
            'Removal request declined and the patient told why.',
        );
    }

    /**
     * Logs a vital on the patient's behalf.
     *
     * A reading taken at the desk, or read back over the phone, previously had
     * nowhere to go: only the patient could write to their own vitals, so staff
     * either asked them to enter it later — which often meant never — or it was
     * left in a note nothing grades or alerts on. Recorded through the same
     * path as the patient's own entry, so the range override, the risk grade
     * and the alert to the care team all behave identically. The row records
     * who entered it.
     */
    public function storeVital(Request $request, User $patient)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);

        $data = $request->validate(VitalRecorder::rules());
        $actor = $request->user();

        $reading = VitalRecorder::record(
            $patient,
            $data,
            $actor,
            'Dr. '.$actor->fullName(),
        );

        DoctorAccess::audit(
            $actor,
            'Logged a vital for '.$patient->fullName(),
            $data['vital_key'].' = '.$data['value'],
        );

        return $this->success(
            ['vital' => $reading->toApiArray()],
            'Reading recorded for the patient.',
            201,
        );
    }

    public function streamDocument(Request $request, User $patient, MedicalDocument $document)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);
        abort_unless($document->user_id === $patient->id, 404);
        if ($error = MedicalDocumentFiles::streamError($document)) {
            return $error;
        }

        return MedicalDocumentFiles::stream($document);
    }

    public function downloadDocument(Request $request, User $patient, MedicalDocument $document)
    {
        DoctorAccess::assertCaseload($request->user(), $patient->id);
        abort_unless($document->user_id === $patient->id, 404);
        if (! $document->storage_path) {
            return $this->error('No file attached.', 404);
        }

        return $this->success([
            'url' => url('/api/v1/doctor/patients/'.$patient->id.'/documents/'.$document->id.'/stream'),
        ]);
    }

    private static function labelFor(string $key): string
    {
        return match ($key) {
            'blood_type' => 'Blood type',
            'gender' => 'Gender',
            'date_of_birth' => 'Date of birth',
            'height_cm' => 'Height',
            'weight_kg' => 'Weight',
            'allergies' => 'Allergies',
            'chronic_conditions' => 'Conditions',
            'current_medications' => 'Medications',
            'address' => 'Address',
            'location_consent' => 'Location consent',
            'no_known_allergies' => 'Allergy status',
            'no_current_medications' => 'Medication status',
            default => $key,
        };
    }
}
