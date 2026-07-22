<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SosEvent extends Model
{
    protected $fillable = [
        'user_id',
        'kind',
        'status',
        'location_label',
        'latitude',
        'longitude',
        'note',
        'responded_by',
        'triggered_at',
        'responded_at',
    ];

    protected function casts(): array
    {
        return [
            'triggered_at' => 'datetime',
            'responded_at' => 'datetime',
            'latitude' => 'float',
            'longitude' => 'float',
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
            'status' => $this->status,
            'location_label' => $this->location_label,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'note' => $this->note,
            'responded_by' => $this->responded_by,
            'triggered_at' => $this->triggered_at?->toIso8601String(),
            'responded_at' => $this->responded_at?->toIso8601String(),
        ];
    }
}
