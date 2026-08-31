<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class MedicalDocument extends Model
{
    protected $fillable = [
        'user_id',
        'title',
        'category',
        'file_type',
        'storage_path',
        'size_bytes',
        'uploaded_by',
        'description',
        'shared_with_doctor_id',
        'uploaded_at',
        'source',
        'issued_report_id',
        'removal_requested_at',
        'removal_reason',
        'removal_declined_at',
        'removal_declined_reason',
    ];

    /** Uploaded by the patient themselves. Their file, theirs to remove. */
    public const SOURCE_PATIENT = 'patient';

    /** Filed by a doctor or admin. Part of the clinical record. */
    public const SOURCE_CLINICIAN = 'clinician';

    /** A report issued from the record after consent. Never removable. */
    public const SOURCE_REPORT = 'report';

    protected function casts(): array
    {
        return [
            'uploaded_at' => 'datetime',
            'size_bytes' => 'integer',
            'removal_requested_at' => 'datetime',
            'removal_declined_at' => 'datetime',
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

    public function toApiArray(): array
    {
        $hasFile = $this->storage_path
            && \App\Support\MedicalDocumentFiles::exists($this->storage_path);

        return [
            'id' => (string) $this->id,
            'title' => $this->title,
            'category' => $this->category,
            'file_type' => $this->file_type,
            'size_bytes' => $this->size_bytes,
            'uploaded_at' => $this->uploaded_at?->toIso8601String(),
            'uploaded_by' => $this->uploaded_by,
            'description' => $this->description,
            'shared_with_doctor_id' => $this->shared_with_doctor_id
                ? (string) $this->shared_with_doctor_id
                : null,
            'has_file' => $hasFile,
            // Lets the app hide a delete control it would only be refused on.
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
        ];
    }
}
