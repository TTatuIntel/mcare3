<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MedicationDose extends Model
{
    protected $fillable = [
        'medication_id',
        'user_id',
        'scheduled_at',
        'taken_at',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'taken_at' => 'datetime',
        ];
    }

    public function medication(): BelongsTo
    {
        return $this->belongsTo(Medication::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'medication_id' => (string) $this->medication_id,
            'scheduled_at' => $this->scheduled_at?->toIso8601String(),
            'taken_at' => $this->taken_at?->toIso8601String(),
            'status' => $this->status,
        ];
    }
}
