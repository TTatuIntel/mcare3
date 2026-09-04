<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\MorphTo;

/**
 * One line in the life of a request the care team shares.
 *
 * Kept separate from `audit_entries` on purpose: the audit log records what
 * staff did for staff and compliance, while this trail is shown to the patient
 * as well — it is the answer to "is anyone actually looking at this?", which a
 * status field alone could never give.
 *
 * The actor's name is frozen into `actor_label` at write time so the timeline
 * still reads correctly after a clinician leaves the practice.
 */
class RequestActivityEvent extends Model
{
    public const OPENED = 'opened';
    public const CLAIMED = 'claimed';
    public const RELEASED = 'released';
    public const ESCALATED = 'escalated';
    public const RESOLVED = 'resolved';
    public const DECLINED = 'declined';
    public const CANCELLED = 'cancelled';
    public const NOTE = 'note';

    protected $fillable = [
        'subject_type',
        'subject_id',
        'actor_user_id',
        'actor_label',
        'action',
        'note',
        'happened_at',
    ];

    protected function casts(): array
    {
        return ['happened_at' => 'datetime'];
    }

    public function subject(): MorphTo
    {
        return $this->morphTo();
    }

    /**
     * Appends an event to [$subject]'s trail.
     *
     * Never throws. A missing timeline line is worth less than the action it
     * describes, and a claim that 500s after the claim has been written leaves
     * two clinicians unsure which of them holds the request.
     */
    public static function record(
        Model $subject,
        string $action,
        string $actorLabel,
        ?int $actorUserId = null,
        ?string $note = null,
    ): void {
        try {
            static::create([
                'subject_type' => $subject->getMorphClass(),
                'subject_id' => $subject->getKey(),
                'actor_user_id' => $actorUserId,
                'actor_label' => $actorLabel,
                'action' => $action,
                'note' => $note,
                'happened_at' => now(),
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'action' => $this->action,
            'actor_label' => $this->actor_label,
            'note' => $this->note,
            'happened_at' => $this->happened_at?->toIso8601String(),
        ];
    }
}
