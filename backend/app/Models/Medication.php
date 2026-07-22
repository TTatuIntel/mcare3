<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Medication extends Model
{
    protected $fillable = [
        'user_id',
        'name',
        'dosage',
        'frequency',
        'form',
        'instructions',
        'prescribed_by',
        'prescribed_by_user_id',
        'start_date',
        'end_date',
        'expiry_date',
        'refills_left',
        'source',
        'active',
    ];

    protected function casts(): array
    {
        return [
            'start_date' => 'date',
            'end_date' => 'date',
            'expiry_date' => 'date',
            'active' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function doses(): HasMany
    {
        return $this->hasMany(MedicationDose::class);
    }

    /**
     * The staff user (doctor) who prescribed this medication, when it
     * originated from a prescription rather than being patient-added.
     */
    public function prescribedByUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'prescribed_by_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'name' => $this->name,
            'dosage' => $this->dosage,
            'frequency' => $this->frequency,
            'form' => $this->form,
            'instructions' => $this->instructions,
            'prescribed_by' => $this->prescribed_by,
            'start_date' => $this->start_date?->toIso8601String(),
            'end_date' => $this->end_date?->toIso8601String(),
            'expiry_date' => $this->expiry_date?->toIso8601String(),
            'refills_left' => $this->refills_left,
            'source' => $this->source,
            'active' => $this->active,
        ];
    }
}
