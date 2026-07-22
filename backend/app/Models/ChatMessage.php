<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ChatMessage extends Model
{
    protected $fillable = [
        'conversation_id',
        'sender_user_id',
        'body',
        'read',
        'sent_at',
    ];

    protected function casts(): array
    {
        return [
            'read' => 'boolean',
            'sent_at' => 'datetime',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(Conversation::class);
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'conversation_id' => (string) $this->conversation_id,
            'sender_id' => $this->sender_user_id ? (string) $this->sender_user_id : 'me',
            'body' => $this->body,
            'sent_at' => $this->sent_at?->toIso8601String(),
            'read' => $this->read,
        ];
    }
}
