<?php

namespace App\Http\Controllers\Concerns;

use App\Models\MedicalDocument;
use App\Models\User;
use App\Support\DocumentDelivery;
use App\Support\DocumentRemoval;
use App\Support\MedicalDocumentFiles;
use Illuminate\Http\Request;

/**
 * Everything staff can do to a patient's documents, written once.
 *
 * Doctors and admins reach the same rows by different routes and must not be
 * able to answer the same question two different ways — but that is exactly
 * what had happened. `DoctorPatientController` and the admin
 * `PatientDocumentsController` each carried their own upload, update, stream,
 * download, honour-removal and decline-removal, one docblock of which said
 * outright that it "deliberately mirrors" the other. Mirrors drift: the admin
 * side had grown a documents index and a removal-request queue filter the
 * doctor side never got, and the two refusal messages for the same refusal
 * already read differently.
 *
 * The host controller supplies only what genuinely differs — how access is
 * gated, what the patient sees in `uploaded_by`, where the stream lives, and
 * how the act is audited. The rules themselves live here, so a change to what
 * staff may do to a record changes it for every kind of staff at once.
 */
trait ManagesPatientDocuments
{
    /**
     * Refuse the caller unless they may act on this patient at all.
     *
     * Doctors assert a caseload; admin staff are gated by route middleware and
     * have nothing further to check, which is the whole reason the admin routes
     * exist separately.
     */
    abstract protected function assertPatientDocumentAccess(Request $request, User $patient): void;

    /**
     * What the patient reads in "who sent me this?".
     *
     * Says the role as well as the name on purpose — "mCare admin · Nia Chebet"
     * answers a different question from "Dr. Nia Chebet", and the patient is
     * entitled to know which one filed a document against their record.
     */
    abstract protected function documentActorLabel(Request $request): string;

    /** The route this caller's clients fetch document bytes from. */
    abstract protected function documentStreamUrl(User $patient, MedicalDocument $document): string;

    /**
     * Record a non-destructive document action in whatever trail this caller
     * writes to. Deletions do not come through here — they go through
     * {@see DocumentRemoval}, which writes the full audit entry itself because
     * that entry has to outlive the row it describes.
     */
    abstract protected function recordDocumentAudit(
        Request $request,
        User $patient,
        MedicalDocument $document,
        string $action,
    ): void;

    /**
     * Documents already in the patient's record, newest first.
     *
     * `?removal_requested=1` narrows it to the ones the patient has asked to
     * have taken out — the queue staff actually work from.
     */
    public function indexDocuments(Request $request, User $patient)
    {
        $this->assertPatientDocumentAccess($request, $patient);

        $query = $patient->medicalDocuments();

        if ($request->boolean('removal_requested')) {
            $documents = $query->whereNotNull('removal_requested_at')
                ->orderByDesc('removal_requested_at')
                ->get();
        } else {
            $documents = $query->orderByDesc('uploaded_at')->get();
        }

        return $this->success([
            'documents' => $documents->map(fn (MedicalDocument $d) => $d->toApiArray())->all(),
        ]);
    }

    public function storeDocument(Request $request, User $patient)
    {
        $this->assertPatientDocumentAccess($request, $patient);

        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $patient->id);
        $actorLabel = $this->documentActorLabel($request);

        $document = $patient->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'mime_type' => $stored['mime'],
            'original_filename' => $stored['original_name'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'uploaded_by' => $actorLabel,
            'uploaded_at' => now(),
            // Part of the clinical record from the moment it is filed, so it
            // cannot later be deleted by staff or by the patient.
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        $this->recordDocumentAudit($request, $patient, $document, 'uploaded');

        // Filing the document is not the same as delivering it. Without this
        // the patient had to notice the new row on their own.
        DocumentDelivery::notifyOwner($document, $actorLabel);

        return $this->success(
            ['document' => $document->toApiArray()],
            'Document sent to patient.',
            201,
        );
    }

    public function updateDocument(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertPatientDocumentAccess($request, $patient);
        $this->assertDocumentBelongsTo($document, $patient);

        $data = MedicalDocumentFiles::validateUpdate($request);
        MedicalDocumentFiles::applyUpdate($document, $data, $request, $patient->id);

        $this->recordDocumentAudit($request, $patient, $document, 'updated');

        return $this->success(
            ['document' => $document->fresh()->toApiArray()],
            'Document updated.',
        );
    }

    /**
     * The file itself. `?download=1` asks for it as an attachment rather than
     * something the browser renders in place.
     */
    public function streamDocument(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertPatientDocumentAccess($request, $patient);
        $this->assertDocumentBelongsTo($document, $patient);

        return MedicalDocumentFiles::streamError($document)
            ?? MedicalDocumentFiles::stream($document, $request->boolean('download'));
    }

    public function downloadDocument(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertPatientDocumentAccess($request, $patient);
        $this->assertDocumentBelongsTo($document, $patient);

        if (! $document->storage_path) {
            return $this->error('No file attached.', 404);
        }

        return $this->success([
            'url' => $this->documentStreamUrl($patient, $document),
            'download_name' => $document->downloadName(),
            'mime_type' => MedicalDocumentFiles::mimeFor($document),
        ]);
    }

    /**
     * Honour a removal the patient asked for — the one deletion staff may do.
     *
     * Guarded by {@see MedicalDocument::isRemovableByStaff()} rather than by
     * who is asking: the authority is the patient's standing request, not the
     * caller's role, so an admin with no request is refused exactly like a
     * doctor with none.
     */
    public function honourDocumentRemoval(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertPatientDocumentAccess($request, $patient);
        $this->assertDocumentBelongsTo($document, $patient);

        $data = $request->validate([
            'note' => 'nullable|string|max:280',
        ]);

        if (! $document->isRemovableByStaff()) {
            return $this->error(
                $document->removalPending()
                    // A pending request on a document staff still may not touch
                    // means it is the patient's own upload or an issued report;
                    // the document itself explains which.
                    ? $document->deleteRefusalReason()
                    : 'The patient has not asked for this document to be '
                        .'removed, so it cannot be deleted. Upload a corrected '
                        .'version, or ask mCare staff to revoke an issued report.',
                403,
            );
        }

        DocumentRemoval::honour(
            $this->audit,
            $request->user(),
            $document,
            isset($data['note']) ? (trim($data['note']) ?: null) : null,
        );

        return $this->success(null, 'Document removed at the patient\'s request.');
    }

    /** Refuse a removal the patient asked for, with a reason they read. */
    public function declineDocumentRemoval(Request $request, User $patient, MedicalDocument $document)
    {
        $this->assertPatientDocumentAccess($request, $patient);
        $this->assertDocumentBelongsTo($document, $patient);

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
    protected function assertDocumentBelongsTo(MedicalDocument $document, User $patient): void
    {
        abort_unless((int) $document->user_id === (int) $patient->id, 404);
    }
}
