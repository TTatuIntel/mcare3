<?php

namespace App\Models;

use App\Support\DocumentCategories;
use App\Support\MedicalDocumentFiles;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class MedicalDocument extends Model
{
    protected $fillable = [
        'user_id',
        'title',
        'category',
        'file_type',
        'mime_type',
        'original_filename',
        'storage_path',
        'size_bytes',
        'uploaded_by',
        'description',
        'shared_with_doctor_id',
        'uploaded_at',
    ];

    protected function casts(): array
    {
        return [
            'uploaded_at' => 'datetime',
            'size_bytes' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * The doctor this document has been explicitly shared with, if any.
     */
    public function sharedWithDoctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'shared_with_doctor_id');
    }

<<<<<<< Updated upstream
=======
    /**
     * The report request this document is the patient's copy of.
     */
    public function issuedReport(): BelongsTo
    {
        return $this->belongsTo(PatientReportRequest::class, 'issued_report_id');
    }

    /**
     * Whether [$user] may delete this document.
     *
     * Deletion is deliberately narrow. A document a clinician filed is part of
     * the clinical record and outlives the person who uploaded it, and an
     * issued report is the evidence of a disclosure the patient consented to —
     * deleting either would erase the record of something that happened. That
     * leaves exactly one deletable case: a patient removing a file they
     * uploaded themselves.
     *
     * Rows written before provenance was tracked have a null source and are
     * treated as patient uploads, which is what they were.
     */
    public function isDeletableBy(User $user): bool
    {
        if ($this->source === self::SOURCE_REPORT
            || $this->source === self::SOURCE_CLINICIAN) {
            return false;
        }

        return (int) $this->user_id === (int) $user->id;
    }

    /** Why deletion was refused, in words the caller can show. */
    public function deleteRefusalReason(): string
    {
        return match ($this->source) {
            self::SOURCE_REPORT => 'An issued report is the record of a disclosure you approved. '
                .'It cannot be deleted. Ask mCare staff to revoke it instead.',
            self::SOURCE_CLINICIAN => 'This document was filed by your care team and is part of '
                .'your clinical record. Ask them to remove it.',
            default => 'You can only delete documents you uploaded yourself.',
        };
    }

    /** A removal the patient has asked for and staff have not answered. */
    public function removalPending(): bool
    {
        return $this->removal_requested_at !== null;
    }

    /**
     * Whether the patient may ask staff to take this document out.
     *
     * Only clinician-filed documents. Their own uploads they simply delete, and
     * an issued report is a disclosure they consented to — deleting that would
     * erase the evidence of something that happened, so it is revoked instead.
     */
    public function canRequestRemoval(): bool
    {
        return $this->source === self::SOURCE_CLINICIAN
            && $this->removal_requested_at === null;
    }

    /**
     * Whether [$staff] may actually delete this on the patient's behalf.
     *
     * The single crack in the no-deletion rule, and the patient's own request
     * is what opens it: staff cannot reach this state on their own initiative.
     */
    public function isRemovableByStaff(): bool
    {
        return $this->source === self::SOURCE_CLINICIAN
            && $this->removal_requested_at !== null;
    }

    /**
     * The filename this document should arrive under.
     *
     * The name it was uploaded with wins — a patient who saved
     * "MRI-2026-03-11.pdf" is looking for that in their Downloads folder, not a
     * slug of whatever they typed in the title box. Server-generated documents
     * and legacy rows fall back to the title plus the extension its recorded
     * type implies; a file with no extension opens in nothing, which is how an
     * issued report came to be undownloadable on a phone.
     */
    public function downloadName(): string
    {
        if (filled($this->original_filename)) {
            return MedicalDocumentFiles::sanitizeFilename((string) $this->original_filename);
        }

        $extension = MedicalDocumentFiles::extensionForMime($this->mime_type)
            ?? $this->extensionFromStoragePath()
            ?? match ($this->file_type) {
                'pdf' => 'pdf',
                'image' => 'jpg',
                'doc' => 'docx',
                default => 'dat',
            };

        $base = Str::slug(Str::limit((string) $this->title, 60, '')) ?: 'document';

        return $base.'.'.$extension;
    }

    private function extensionFromStoragePath(): ?string
    {
        if (! $this->storage_path) {
            return null;
        }

        $extension = strtolower(pathinfo($this->storage_path, PATHINFO_EXTENSION));

        return $extension === '' ? null : $extension;
    }

    /**
     * The one wire shape for a document.
     *
     * {@see \App\Http\Resources\MedicalDocumentResource} is a thin wrapper over
     * this, so the patient's list, the doctor's chart and the admin queue
     * cannot describe the same row three subtly different ways — which they had
     * already begun to, with two independent copies of this array drifting
     * apart field by field.
     *
     * @return array<string, mixed>
     */
>>>>>>> Stashed changes
    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'title' => $this->title,
            'category' => $this->category,
            'category_label' => DocumentCategories::label($this->category),
            'file_type' => $this->file_type,
            // The real content type and filename, so the app hands the browser
            // and the share sheet what the server actually holds rather than a
            // guess made from `file_type`.
            'mime_type' => MedicalDocumentFiles::mimeFor($this),
            'download_name' => $this->downloadName(),
            'size_bytes' => $this->size_bytes,
            'uploaded_at' => $this->uploaded_at?->toIso8601String(),
            'uploaded_by' => $this->uploaded_by,
            'description' => $this->description,
            'shared_with_doctor_id' => $this->shared_with_doctor_id
                ? (string) $this->shared_with_doctor_id
                : null,
<<<<<<< Updated upstream
            'has_file' => $hasFile,
=======
            'has_file' => MedicalDocumentFiles::exists($this->storage_path),
            // Lets the app hide a delete control it would only be refused on,
            // and label where a document came from.
            'source' => $this->source ?? self::SOURCE_PATIENT,
            'issued_report_id' => $this->issued_report_id
                ? (string) $this->issued_report_id
                : null,
        ] + $this->removalApiArray();
    }

    /**
     * The removal-request state, shared by every serialiser so the patient's
     * list, the doctor's chart and the admin queue all describe one document
     * the same way.
     *
     * @return array<string, mixed>
     */
    public function removalApiArray(): array
    {
        return [
            'removal_requested' => $this->removalPending(),
            'removal_requested_at' => $this->removal_requested_at?->toIso8601String(),
            'removal_reason' => $this->removal_reason,
            'removal_declined_at' => $this->removal_declined_at?->toIso8601String(),
            'removal_declined_reason' => $this->removal_declined_reason,
            'can_request_removal' => $this->canRequestRemoval(),
>>>>>>> Stashed changes
        ];
    }
}
