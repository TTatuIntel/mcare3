<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\MedicalDocument;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use App\Support\DocumentDelivery;
use App\Support\DocumentRemoval;
use App\Support\MedicalDocumentFiles;
use Illuminate\Http\Request;

/**
 * Lets admin / mCare assistant staff file documents into a patient's record.
 *
 * Doctors could already do this and admins could not, which left the paperwork
 * that is not a doctor's to send — an insurance letter, a scanned consent, a
 * corrected lab result received by the office — with no route into the record
 * at all. Staff were reduced to emailing it, which puts clinical documents
 * outside the audited store entirely.
 *
 * Nothing in a patient's record disappears on staff say-so: a wrong document is
 * superseded by a corrected upload and a report that should not have gone out is
 * revoked — both leave a trace, which deletion does not. The one exception is
 * `honourRemoval`, and it is not staff-initiated: it requires a standing request
 * from the patient, which is the only authority that can take a document out of
 * their own record.
 *
 * Deliberately mirrors {@see \App\Http\Controllers\Api\V1\DoctorPatientController}'s
 * document methods so the patient sees no difference in where a document came
 * from beyond the `uploaded_by` label. Access is gated by the route's
 * permission middleware rather than a caseload check: admin staff are not on a
 * caseload, which is the whole reason this exists.
 */
class PatientDocumentsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    /**
     * Documents already in the patient's record, newest first.
     *
     * `?removal_requested=1` narrows it to the ones the patient has asked to
     * have taken out — the queue staff actually work from.
     */
    public function index(Request $request, User $patient)
    {
        if ($request->boolean('removal_requested')) {
            return $this->success([
                'documents' => $patient->medicalDocuments()
                    ->whereNotNull('removal_requested_at')
                    ->orderByDesc('removal_requested_at')
                    ->get()
                    ->map(fn (MedicalDocument $d) => $d->toApiArray()),
            ]);
        }

        $documents = $patient->medicalDocuments()
            ->orderByDesc('uploaded_at')
            ->get()
            ->map(fn (MedicalDocument $d) => $d->toApiArray());

        return $this->success(['documents' => $documents]);
    }

    public function store(Request $request, User $patient)
    {
        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $patient->id);

        $document = $patient->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'uploaded_by' => $this->actorLabel($request),
            'uploaded_at' => now(),
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        $this->audit->record(
            $request->user(),
            'patient.document_uploaded',
            $document->title.' for '.$patient->fullName(),
            'activity',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'document_id' => $document->id,
                'category' => $document->category,
            ],
        );

        DocumentDelivery::notifyOwner($document, $this->actorLabel($request));

        return $this->success(
            ['document' => $document->toApiArray()],
            'Document sent to patient.',
            201,
        );
    }

    public function update(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertOwnedBy($document, $patient);

        $data = MedicalDocumentFiles::validateUpdate($request);
        MedicalDocumentFiles::applyUpdate($document, $data, $request, $patient->id);

        $this->audit->record(
            $request->user(),
            'patient.document_updated',
            $document->title.' for '.$patient->fullName(),
            'activity',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'document_id' => $document->id,
            ],
        );

        return $this->success(
            ['document' => $document->fresh()->toApiArray()],
            'Document updated.',
        );
    }

    public function stream(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertOwnedBy($document, $patient);

        return MedicalDocumentFiles::streamError($document)
            ?? MedicalDocumentFiles::stream($document);
    }

    /**
     * Honour a removal the patient asked for — the one deletion staff may do.
     *
     * Guarded by {@see MedicalDocument::isRemovableByStaff()} rather than by
     * this route being admin-only: the authority is the patient's request, not
     * the caller's role, so an admin with no standing request is refused
     * exactly like anyone else.
     */
    public function honourRemoval(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertOwnedBy($document, $patient);

        $data = $request->validate([
            'note' => 'nullable|string|max:280',
        ]);

        if (! $document->isRemovableByStaff()) {
            return $this->error(
                $document->removalPending()
                    ? $document->deleteRefusalReason()
                    : 'The patient has not asked for this document to be '
                        .'removed, so it cannot be deleted.',
                403,
            );
        }

        DocumentRemoval::honour(
            $this->audit,
            $request->user(),
            $document,
            $data['note'] ?? null,
        );

        return $this->success(null, 'Document removed and the patient told.');
    }

    /** Refuse a removal request, with a reason the patient reads. */
    public function declineRemoval(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertOwnedBy($document, $patient);

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
     * A document belongs to exactly one patient. Answering 404 rather than 403
     * keeps a mismatched pair from confirming that the id exists at all.
     */
    private function assertOwnedBy(MedicalDocument $document, User $patient): void
    {
        abort_unless($document->user_id === $patient->id, 404);
    }

    /**
     * Patients read this string in their documents list, so it says the role
     * rather than a bare name — "who sent me this?" is the first question.
     */
    private function actorLabel(Request $request): string
    {
        $user = $request->user();
        $role = $user->role === 'mcare_assistant' ? 'mCare team' : 'mCare admin';

        return $role.' · '.$user->fullName();
    }
}
