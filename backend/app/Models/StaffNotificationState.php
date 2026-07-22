<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffNotificationState extends Model
{
    protected $fillable = [
        'user_id',
        'notification_key',
        'read_at',
        'resolved_at',
    ];

    protected function casts(): array
    {
        return [
            'read_at' => 'datetime',
            'resolved_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function toApiArray(): array
    {
        return [
            'key' => $this->notification_key,
            'read' => $this->read_at !== null,
            'resolved' => $this->resolved_at !== null,
        ];
    }
}
