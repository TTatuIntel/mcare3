<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CareAssignment extends Model
{
    protected $fillable = [
        'patient_user_id',
        'provider_id',
        'role',
        'assigned_at',
        'ended_at',
    ];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'patient_user_id');
    }

    public function provider(): BelongsTo
    {
        return $this->belongsTo(CareProvider::class, 'provider_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'patient_user_id' => (string) $this->patient_user_id,
            'provider_id' => (string) $this->provider_id,
            'role' => $this->role,
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'ended_at' => $this->ended_at?->toIso8601String(),
        ];
    }
}
