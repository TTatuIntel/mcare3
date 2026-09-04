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
        'scheduled_for',
        'serve_time',
        'condition_tag',
        'items',
        'source',
        'adherence',
        'logged_at',
        'patient_note',
    ];

    /** Plans the patient wrote for themselves, rather than clinician-assigned. */
    public const SOURCE_PATIENT = 'patient';

    public const SOURCE_CARE_TEAM = 'care_team';

    public const ADHERENCE = ['pending', 'followed', 'partial', 'skipped'];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
            'scheduled_for' => 'date',
            'logged_at' => 'datetime',
            'items' => 'array',
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

    /**
     * The day this plan belongs to. Rows written before scheduling existed
     * fall back to the day they were assigned, so no plan is ever undated.
     */
    public function scheduledDay(): \Illuminate\Support\Carbon
    {
        return ($this->scheduled_for ?? $this->assigned_at ?? $this->created_at ?? now())
            ->copy()
            ->startOfDay();
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
                : ($this->source === self::SOURCE_PATIENT ? 'You' : 'System'),
            'scheduled_for' => $this->scheduledDay()->toDateString(),
            'serve_time' => $this->serve_time,
            'condition_tag' => $this->condition_tag,
            'items' => $this->items ?? [],
            'source' => $this->source ?? self::SOURCE_CARE_TEAM,
            'adherence' => $this->adherence ?? 'pending',
            'logged_at' => $this->logged_at?->toIso8601String(),
            'patient_note' => $this->patient_note,
        ];
    }
}
