<?php

namespace App\Models;

use App\Support\PatientReportSections;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A customised patient report an admin has asked for.
 *
 * The row is a permission ledger first and a document second: it records
 * exactly which sections were requested, that the patient consented to those
 * sections, and that a doctor signed off before anything was disclosed. The
 * assembled content is only frozen into `snapshot` at issue time.
 */
class PatientReportRequest extends Model
{
    public const STATUS_DRAFT = 'draft';

    public const STATUS_PENDING_CONSENT = 'pending_consent';

    public const STATUS_CONSENTED = 'consented';

    public const STATUS_DECLINED = 'declined';

    public const STATUS_EXPIRED = 'expired';

    public const STATUS_PENDING_SIGNATURE = 'pending_signature';

    public const STATUS_SIGNED = 'signed';

    public const STATUS_ISSUED = 'issued';

    public const STATUS_REVOKED = 'revoked';

    /** Wrong-code attempts allowed before the consent challenge is burned. */
    public const MAX_CONSENT_ATTEMPTS = 5;

    protected $fillable = [
        'patient_user_id',
        'requested_by_user_id',
        'doctor_user_id',
        'title',
        'purpose',
        'recipient',
        'sections',
        'consent_required',
        'signature_required',
        'status',
        'consent_code_hash',
        'consent_token',
        'consent_channel',
        'consent_sent_at',
        'consent_expires_at',
        'consent_attempts',
        'consented_at',
        'consent_method',
        'declined_at',
        'decline_reason',
        'signed_at',
        'signature_name',
        'signature_note',
        'issued_at',
        'revoked_at',
        'revoke_reason',
        'snapshot',
    ];

    protected $hidden = [
        'consent_code_hash',
        'consent_token',
    ];

    protected function casts(): array
    {
        return [
            'sections' => 'array',
            'consent_required' => 'boolean',
            'signature_required' => 'boolean',
            'consent_sent_at' => 'datetime',
            'consent_expires_at' => 'datetime',
            'consented_at' => 'datetime',
            'declined_at' => 'datetime',
            'signed_at' => 'datetime',
            'issued_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'patient_user_id');
    }

    public function requestedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by_user_id');
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'doctor_user_id');
    }

    public function consentExpired(): bool
    {
        return $this->consent_expires_at !== null
            && $this->consent_expires_at->isPast();
    }

    public function isTerminal(): bool
    {
        return in_array($this->status, [
            self::STATUS_DECLINED,
            self::STATUS_EXPIRED,
            self::STATUS_REVOKED,
        ], true);
    }

    /**
     * Consent is satisfied when it was never needed, or when the patient
     * granted it and has not since withdrawn.
     */
    public function consentSatisfied(): bool
    {
        return ! $this->consent_required || $this->consented_at !== null;
    }

    public function signatureSatisfied(): bool
    {
        return ! $this->signature_required || $this->signed_at !== null;
    }

    public function readyToIssue(): bool
    {
        return ! $this->isTerminal()
            && $this->issued_at === null
            && $this->consentSatisfied()
            && $this->signatureSatisfied();
    }

    /**
     * The next thing a human has to do — drives the status chip in every UI.
     */
    public function blockedOn(): ?string
    {
        if ($this->isTerminal() || $this->issued_at !== null) {
            return null;
        }
        if (! $this->consentSatisfied()) {
            return 'patient_consent';
        }
        if (! $this->signatureSatisfied()) {
            return 'doctor_signature';
        }

        return 'issue';
    }

    public function statusLabel(): string
    {
        return match ($this->status) {
            self::STATUS_DRAFT => 'Draft',
            self::STATUS_PENDING_CONSENT => 'Awaiting patient consent',
            self::STATUS_CONSENTED => 'Consent granted',
            self::STATUS_DECLINED => 'Declined by patient',
            self::STATUS_EXPIRED => 'Consent expired',
            self::STATUS_PENDING_SIGNATURE => 'Awaiting doctor signature',
            self::STATUS_SIGNED => 'Signed — ready to issue',
            self::STATUS_ISSUED => 'Issued',
            self::STATUS_REVOKED => 'Revoked',
            default => ucfirst($this->status),
        };
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        $sections = $this->sections ?? [];

        return [
            'id' => (string) $this->id,
            'patient_id' => (string) $this->patient_user_id,
            'patient_name' => $this->patient?->fullName(),
            'patient_unique_id' => $this->patient?->unique_id,
            'requested_by_name' => $this->requestedBy?->fullName(),
            'doctor_id' => $this->doctor_user_id === null ? null : (string) $this->doctor_user_id,
            'doctor_name' => $this->doctor?->fullName(),
            'title' => $this->title,
            'purpose' => $this->purpose,
            'recipient' => $this->recipient,
            'sections' => $sections,
            'section_labels' => array_map(
                fn (string $k) => PatientReportSections::label($k),
                $sections,
            ),
            'consent_required' => (bool) $this->consent_required,
            'signature_required' => (bool) $this->signature_required,
            'status' => $this->status,
            'status_label' => $this->statusLabel(),
            'blocked_on' => $this->blockedOn(),
            'consent_channel' => $this->consent_channel,
            'consent_sent_at' => $this->consent_sent_at?->toIso8601String(),
            'consent_expires_at' => $this->consent_expires_at?->toIso8601String(),
            'consent_expired' => $this->consentExpired(),
            'consent_attempts' => (int) $this->consent_attempts,
            'consented_at' => $this->consented_at?->toIso8601String(),
            'consent_method' => $this->consent_method,
            'declined_at' => $this->declined_at?->toIso8601String(),
            'decline_reason' => $this->decline_reason,
            'signed_at' => $this->signed_at?->toIso8601String(),
            'signature_name' => $this->signature_name,
            'signature_note' => $this->signature_note,
            'issued_at' => $this->issued_at?->toIso8601String(),
            'revoked_at' => $this->revoked_at?->toIso8601String(),
            'revoke_reason' => $this->revoke_reason,
            'created_at' => $this->created_at?->toIso8601String(),
            'has_snapshot' => $this->snapshot !== null,
        ];
    }

    /**
     * The patient's own view of this request: the staff shape plus plain
     * descriptions of every section and whether it is waiting on them.
     *
     * Both the consent screen and the session payload build their rows here,
     * so the badge, the home prompt and the approval screen can never disagree
     * about what is outstanding.
     *
     * @return array<string, mixed>
     */
    public function toPatientApiArray(): array
    {
        return $this->toApiArray() + [
            'section_details' => array_map(fn (string $k) => [
                'key' => $k,
                'label' => PatientReportSections::label($k),
                'description' => PatientReportSections::CATALOG[$k]['description'] ?? '',
            ], $this->sections ?? []),
            'awaiting_me' => $this->status === self::STATUS_PENDING_CONSENT
                && ! $this->consentExpired(),
        ];
    }
}
