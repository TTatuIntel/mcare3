<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupportTicketReply extends Model
{
    protected $fillable = [
        'ticket_id',
        'author_user_id',
        'author',
        'is_staff',
        'body',
        'sent_at',
    ];

    protected function casts(): array
    {
        return [
            'is_staff' => 'boolean',
            'sent_at' => 'datetime',
        ];
    }

    public function ticket(): BelongsTo
    {
        return $this->belongsTo(SupportTicket::class, 'ticket_id');
    }

    public function authorUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'author' => $this->author,
            'body' => $this->body,
            'sent_at' => $this->sent_at?->toIso8601String(),
            'is_staff' => $this->is_staff,
        ];
    }
}
