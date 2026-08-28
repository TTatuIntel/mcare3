<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Conversation extends Model
{
    protected $fillable = [
        'user_id',
        'participant_user_id',
        'participant_name',
        'participant_role',
        'participant_specialty',
        'unread_count',
        'last_message_at',
    ];

    protected function casts(): array
    {
        return [
            'last_message_at' => 'datetime',
            'unread_count' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function participant(): BelongsTo
    {
        return $this->belongsTo(User::class, 'participant_user_id');
    }

    public function messages(): HasMany
    {
        return $this->hasMany(ChatMessage::class);
    }

    public function toApiArray(?User $viewer = null): array
    {
        $last = $this->relationLoaded('messages')
            ? $this->messages->sortByDesc('sent_at')->first()
            : $this->messages()->latest('sent_at')->first();

        return [
            'id' => (string) $this->id,
            'participant' => $this->participantPayload($viewer),
            'last_message' => $last?->toApiArray(),
            'unread_count' => $this->unreadCountFor($viewer),
        ];
    }

    private function unreadCountFor(?User $viewer): int
    {
        $viewerId = $viewer?->id ?? $this->user_id;
        $isParticipant = (int) $this->user_id === (int) $viewerId
            || (int) $this->participant_user_id === (int) $viewerId;

        if (! $isParticipant) {
            return 0;
        }

        $precomputed = $this->getAttribute('unread_messages_count');
        if ($precomputed !== null) {
            return (int) $precomputed;
        }

        return $this->messages()
            ->where('sender_user_id', '!=', $viewerId)
            ->where('read', false)
            ->count();
    }

    private function participantPayload(?User $viewer): array
    {
        if ($viewer && in_array($viewer->role, ['admin', 'mcare_assistant'], true)) {
            $owner = $this->relationLoaded('user') ? $this->user : $this->user()->first();
            if ($owner && (string) $owner->id !== (string) $viewer->id) {
                return [
                    'id' => (string) $owner->id,
                    'name' => $owner->fullName(),
                    'role' => $owner->role,
                    'specialty' => null,
                ];
            }

            $participant = $this->relationLoaded('participant')
                ? $this->participant
                : $this->participant()->first();
            if ($participant) {
                return [
                    'id' => (string) $participant->id,
                    'name' => $participant->fullName(),
                    'role' => $participant->role,
                    'specialty' => $this->participant_specialty,
                ];
            }
        }

        return [
            'id' => (string) ($this->participant_user_id ?? ''),
            'name' => $this->participant_name,
            'role' => $this->participant_role,
            'specialty' => $this->participant_specialty,
        ];
    }
}
