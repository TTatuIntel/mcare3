<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MealPlan extends Model
{
    protected $fillable = [
        'patient_user_id',
        'assigned_by_user_id',
        'title',
        'meal_type',
        'description',
        'calories',
        'protein',
        'carbs',
        'fat',
        'notes',
        'assigned_at',
    ];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
        ];
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'patient_user_id');
    }

    public function assignedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_by_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'patient_id' => (string) $this->patient_user_id,
            'patient_name' => $this->patient?->fullName() ?? '',
            'title' => $this->title,
            'meal_type' => $this->meal_type,
            'description' => $this->description,
            'calories' => $this->calories,
            'protein' => $this->protein,
            'carbs' => $this->carbs,
            'fat' => $this->fat,
            'notes' => $this->notes,
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'assigned_by' => $this->assignedBy
                ? 'Dr. '.$this->assignedBy->fullName()
                : 'System',
        ];
    }
}
