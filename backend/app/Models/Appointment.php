<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Appointment extends Model
{
    protected $fillable = [
        'user_id',
        'doctor_user_id',
        'doctor_name',
        'doctor_specialty',
        'scheduled_at',
        'duration_minutes',
        'type',
        'status',
        'reason',
        'location_or_link',
        'cancellation_reason',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'doctor_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'doctor_id' => (string) ($this->doctor_user_id ?? ''),
            'doctor_name' => $this->doctor_name,
            'doctor_specialty' => $this->doctor_specialty,
            'scheduled_at' => $this->scheduled_at?->toIso8601String(),
            'duration_minutes' => $this->duration_minutes,
            'type' => $this->type,
            'status' => $this->status,
            'reason' => $this->reason,
            'location_or_link' => $this->location_or_link,
            'cancellation_reason' => $this->cancellation_reason,
        ];
    }
}
