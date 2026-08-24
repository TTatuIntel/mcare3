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
        'assigned_reason',
        'assigned_by',
        'ended_at',
        'ended_reason',
        'ended_by',
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

    public function assigner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_by');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'patient_user_id' => (string) $this->patient_user_id,
            'patient_id' => (string) $this->patient_user_id,
            'provider_id' => (string) $this->provider_id,
            'role' => $this->role,
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'assigned_reason' => $this->assigned_reason,
            'ended_at' => $this->ended_at?->toIso8601String(),
            'ended_reason' => $this->ended_reason,
        ];
    }

    /**
     * Row shape used by every admin surface — adds the display names and the
     * provider's linked user id so the UI can pivot between the directory and
     * the care_providers table.
     */
    public function toAdminArray(): array
    {
        return $this->toApiArray() + [
            'patient_name' => $this->patient?->fullName(),
            'provider_name' => $this->provider?->name,
            'provider_specialty' => $this->provider?->specialty,
            'provider_user_id' => $this->provider?->user_id === null
                ? null
                : (string) $this->provider->user_id,
            'assigned_by_name' => $this->assigner?->fullName(),
        ];
    }
}
