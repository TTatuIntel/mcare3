<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphMany;

/**
 * The patient asking for a document they do not have.
 *
 * Uploading works in one direction only: the patient can put a file into their
 * record, and clinicians can file one for them, but a patient who needs a
 * referral letter, a fit-note or a copy of last year's discharge summary had
 * no way to ask for it inside the app. They rang the desk, and nothing about
 * the ask was recorded anywhere.
 *
 * This is the other direction, and it deliberately mirrors a vital report
 * request: addressed either to the whole care team or to one named doctor,
 * visible to the team either way, claimable by exactly one person, and closed
 * out by a document appearing in the patient's list.
 */
class DocumentRequest extends Model
{
    public const PENDING = 'pending';
    public const IN_PROGRESS = 'in_progress';
    public const FULFILLED = 'fulfilled';
    public const DECLINED = 'declined';
    public const CANCELLED = 'cancelled';

    public const TARGET_TEAM = 'team';
    public const TARGET_DOCTOR = 'doctor';

    protected $fillable = [
        'user_id',
        'title',
        'category',
        'note',
        'target',
        'target_doctor_id',
        'needed_by',
        'status',
        'claimed_by',
        'claimed_by_name',
        'claimed_at',
        'resolved_at',
        'resolved_by_name',
        'resolution_note',
        'decline_reason',
        'document_id',
    ];

    protected function casts(): array
    {
        return [
            'needed_by' => 'date',
            'claimed_at' => 'datetime',
            'resolved_at' => 'datetime',
        ];
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function targetDoctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'target_doctor_id');
    }

    public function claimant(): BelongsTo
    {
        return $this->belongsTo(User::class, 'claimed_by');
    }

    public function document(): BelongsTo
    {
        return $this->belongsTo(MedicalDocument::class, 'document_id');
    }

    public function events(): MorphMany
    {
        return $this->morphMany(RequestActivityEvent::class, 'subject')
            ->orderBy('happened_at');
    }

    public function isOpen(): bool
    {
        return in_array($this->status, [self::PENDING, self::IN_PROGRESS], true);
    }

    public function isClaimed(): bool
    {
        return $this->claimed_by !== null;
    }

    public function isClaimedBy(User $user): bool
    {
        return (int) $this->claimed_by === (int) $user->id;
    }

    /** Overdue only counts while the request is still open. */
    public function isOverdue(): bool
    {
        return $this->isOpen()
            && $this->needed_by !== null
            && $this->needed_by->isPast();
    }

    /** @see VitalReportRequest::claimFor() for why the guard is in the query. */
    public function claimFor(User $user, string $label): bool
    {
        $claimed = static::whereKey($this->getKey())
            ->whereNull('claimed_by')
            ->whereIn('status', [self::PENDING, self::IN_PROGRESS])
            ->update([
                'claimed_by' => $user->id,
                'claimed_by_name' => $label,
                'claimed_at' => now(),
                'status' => self::IN_PROGRESS,
                'updated_at' => now(),
            ]);

        if ($claimed === 0) {
            return false;
        }

        $this->refresh();
        RequestActivityEvent::record($this, RequestActivityEvent::CLAIMED, $label, $user->id);

        return true;
    }

    public function release(User $user, string $label, ?string $note = null): void
    {
        $this->update([
            'claimed_by' => null,
            'claimed_by_name' => null,
            'claimed_at' => null,
            'status' => self::PENDING,
        ]);

        RequestActivityEvent::record(
            $this,
            RequestActivityEvent::RELEASED,
            $label,
            $user->id,
            $note,
        );
    }

    public function waitingOnLabel(): string
    {
        if ($this->claimed_by_name) {
            return $this->claimed_by_name;
        }
        if ($this->target === self::TARGET_DOCTOR && $this->targetDoctor) {
            return 'Dr. '.$this->targetDoctor->fullName();
        }

        return 'mCare care team';
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'title' => $this->title,
            'category' => $this->category,
            'note' => $this->note,
            'target' => $this->target,
            'target_doctor_id' => $this->target_doctor_id
                ? (string) $this->target_doctor_id
                : null,
            'target_doctor_name' => $this->targetDoctor?->fullName(),
            'needed_by' => $this->needed_by?->toDateString(),
            'overdue' => $this->isOverdue(),
            'status' => $this->status,
            'created_at' => $this->created_at?->toIso8601String(),
            'claimed_by' => $this->claimed_by ? (string) $this->claimed_by : null,
            'claimed_by_name' => $this->claimed_by_name,
            'claimed_at' => $this->claimed_at?->toIso8601String(),
            'waiting_on' => $this->waitingOnLabel(),
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'resolved_by_name' => $this->resolved_by_name,
            'resolution_note' => $this->resolution_note,
            'decline_reason' => $this->decline_reason,
            'document_id' => $this->document_id ? (string) $this->document_id : null,
            'events' => $this->relationLoaded('events')
                ? $this->events->map->toApiArray()->all()
                : [],
        ];
    }

    public function toStaffArray(?User $viewer = null): array
    {
        return $this->toApiArray() + [
            'patient_id' => (string) $this->user_id,
            'patient_name' => $this->patient?->fullName(),
            'claimed_by_me' => $viewer !== null && $this->isClaimedBy($viewer),
            'claimable' => $this->isOpen() && ! $this->isClaimed(),
            // A request addressed to one doctor is still visible to the whole
            // team — this is what lets their app say so rather than treat it
            // as unassigned work.
            'addressed_to_me' => $viewer !== null
                && (int) $this->target_doctor_id === (int) $viewer->id,
        ];
    }
}
