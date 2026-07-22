<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AppNotification extends Model
{
    protected $table = 'app_notifications';

    protected $fillable = [
        'user_id',
        'kind',
        'title',
        'body',
        'action_route',
        'action_arguments',
        'read',
        'resolved',
        'resolved_at',
    ];

    protected function casts(): array
    {
        return [
            'action_arguments' => 'array',
            'read' => 'boolean',
            'resolved' => 'boolean',
            'resolved_at' => 'datetime',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'kind' => $this->kind,
            'title' => $this->title,
            'body' => $this->body,
            'action_route' => $this->action_route,
            'action_arguments' => $this->action_arguments,
            'read' => $this->read,
            'resolved' => $this->resolved,
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
