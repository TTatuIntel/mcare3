<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphMany;

/**
 * A patient's ask for a summary of their readings over a window.
 *
 * Visibility and ownership are deliberately different things here. Every
 * clinician assigned to the patient sees the request — that is what makes it
 * team work rather than one doctor's inbox — but only one of them can hold it,
 * and holding it is what authorises finishing it. Without that, the same
 * report got written twice and neither author knew about the other.
 *
 * The escalation chain (`current_responder`) still runs underneath: it decides
 * who is *answerable* when nobody has picked the request up. A claim overrides
 * it in practice, because someone acting beats someone accountable.
 */
class VitalReportRequest extends Model
{
    public const PENDING = 'pending';
    public const IN_PROGRESS = 'in_progress';
    public const FULFILLED = 'fulfilled';
    public const CANCELLED = 'cancelled';

    protected $fillable = [
        'user_id',
        'range_from',
        'range_to',
        'vitals',
        'note',
        'status',
        'current_responder',
        'last_escalated_at',
        'claimed_by',
        'claimed_by_name',
        'claimed_at',
        'responded_at',
        'responded_by',
        'response_note',
        'resolved_at',
        'document_id',
        'signed_by_user_id',
        'signed_by',
        'signed_by_role',
        'signed_at',
    ];

    protected function casts(): array
    {
        return [
            'range_from' => 'date',
            'range_to' => 'date',
            'vitals' => 'array',
            'last_escalated_at' => 'datetime',
            'claimed_at' => 'datetime',
            'responded_at' => 'datetime',
            'resolved_at' => 'datetime',
            'signed_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function claimant(): BelongsTo
    {
        return $this->belongsTo(User::class, 'claimed_by');
    }

    /** The filed report that closed this out, if it has been finished. */
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

    /**
     * Takes ownership of the request for [$user], if nobody else holds it.
     *
     * The guard is in the WHERE clause rather than in PHP so two clinicians
     * tapping "work on this" at the same moment cannot both win: the second
     * UPDATE matches no rows and the caller is told who got there first.
     */
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

    /** Hands the request back to the shared queue. */
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

    /** Who the patient is waiting on, in words they can read. */
    public function waitingOnLabel(): string
    {
        if ($this->claimed_by_name) {
            return $this->claimed_by_name;
        }

        return match ($this->current_responder) {
            'doctor' => 'Your care team',
            'mcareAssistant' => 'mCare assistant',
            'admin' => 'Care admin',
            default => 'Your care team',
        };
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'from' => $this->range_from?->toIso8601String(),
            'to' => $this->range_to?->toIso8601String(),
            'vitals' => $this->vitals ?? [],
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'current_responder' => $this->current_responder,
            'note' => $this->note,
            'claimed_by' => $this->claimed_by ? (string) $this->claimed_by : null,
            'claimed_by_name' => $this->claimed_by_name,
            'claimed_at' => $this->claimed_at?->toIso8601String(),
            'waiting_on' => $this->waitingOnLabel(),
            'responded_at' => $this->responded_at?->toIso8601String(),
            'responded_by' => $this->responded_by,
            'response_note' => $this->response_note,
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'document_id' => $this->document_id ? (string) $this->document_id : null,
            'signed_by' => $this->signed_by,
            'signed_by_role' => $this->signed_by_role,
            'signed_at' => $this->signed_at?->toIso8601String(),
            'last_escalated_at' => $this->last_escalated_at?->toIso8601String(),
            'events' => $this->relationLoaded('events')
                ? $this->events->map->toApiArray()->all()
                : [],
        ];
    }

    /**
     * The staff-side row. Adds who the patient is and whether *this* viewer is
     * the one holding it — the single fact a shared queue has to answer before
     * anyone can decide whether to act.
     */
    public function toStaffArray(?User $viewer = null): array
    {
        return $this->toApiArray() + [
            'patient_id' => (string) $this->user_id,
            'patient_name' => $this->user?->fullName(),
            'claimed_by_me' => $viewer !== null && $this->isClaimedBy($viewer),
            'claimable' => $this->isOpen() && ! $this->isClaimed(),
        ];
    }
}
