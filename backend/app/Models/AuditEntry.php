<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AuditEntry extends Model
{
    protected $fillable = [
        'actor_user_id',
        'actor_label',
        'action',
        'target',
        'category',
        'meta',
        'happened_at',
    ];

    protected function casts(): array
    {
        return [
            'meta' => 'array',
            'happened_at' => 'datetime',
        ];
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'happened_at' => $this->happened_at?->toIso8601String(),
            'actor' => $this->actor_label,
            'action' => $this->action,
            'target' => $this->target,
            'category' => $this->category,
        ];
    }
}
