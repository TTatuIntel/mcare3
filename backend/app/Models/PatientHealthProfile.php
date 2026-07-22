<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PatientHealthProfile extends Model
{
    protected $fillable = [
        'user_id',
        'blood_type',
        'gender',
        'date_of_birth',
        'height_cm',
        'weight_kg',
        'allergies',
        'chronic_conditions',
        'current_medications',
        'address',
        'location_consent',
        'no_known_allergies',
        'no_current_medications',
    ];

    protected function casts(): array
    {
        return [
            'date_of_birth' => 'date',
            'height_cm' => 'float',
            'weight_kg' => 'float',
            'allergies' => 'array',
            'chronic_conditions' => 'array',
            'current_medications' => 'array',
            'location_consent' => 'boolean',
            'no_known_allergies' => 'boolean',
            'no_current_medications' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function toApiArray(): array
    {
        return [
            'blood_type' => $this->blood_type,
            'gender' => $this->gender,
            'date_of_birth' => $this->date_of_birth?->format('Y-m-d'),
            'height_cm' => $this->height_cm,
            'weight_kg' => $this->weight_kg,
            'allergies' => $this->allergies ?? [],
            'chronic_conditions' => $this->chronic_conditions ?? [],
            'current_medications' => $this->current_medications ?? [],
            'address' => $this->address,
            'location_consent' => $this->location_consent,
            'no_known_allergies' => $this->no_known_allergies,
            'no_current_medications' => $this->no_current_medications,
        ];
    }
}
