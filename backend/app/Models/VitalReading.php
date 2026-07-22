<?php

namespace App\Models;

use App\Support\VitalLabels;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VitalReading extends Model
{
    protected $fillable = [
        'user_id',
        'vital_key',
        'value',
        'secondary_value',
        'risk',
        'recorded_at',
        'note',
    ];

    protected function casts(): array
    {
        return [
            'value' => 'float',
            'secondary_value' => 'float',
            'recorded_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function displayValue(): string
    {
        if ($this->vital_key === 'bloodPressure' && $this->secondary_value !== null) {
            return sprintf(
                '%d/%d mmHg',
                (int) round($this->value),
                (int) round($this->secondary_value)
            );
        }

        $unit = VitalLabels::unit($this->vital_key);
        $formatted = match ($this->vital_key) {
            'temperature', 'weight' => number_format($this->value, 1, '.', ''),
            default => (string) (int) round($this->value),
        };

        return $unit !== '' ? "$formatted $unit" : $formatted;
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'vital' => $this->vital_key,
            'vital_key' => $this->vital_key,
            'value' => $this->value,
            'secondary_value' => $this->secondary_value,
            'display_value' => $this->displayValue(),
            'risk' => $this->risk,
            'recorded_at' => $this->recorded_at?->toIso8601String(),
            'note' => $this->note,
        ];
    }
}
