<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SosEvent extends Model
{
    protected $fillable = [
        'user_id',
        'kind',
        'status',
        'resolution',
        'resolution_note',
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

    /**
     * Named endings. A responder picks one, or picks `other` and says what
     * happened in their own words — a list can never cover every emergency,
     * and forcing the nearest wrong option corrupts the record.
     */
    public const RESOLUTIONS = [
        'patient_safe',
        'transported',
        'treated_on_site',
        'care_team_handling',
        'unreachable',
        'other',
    ];

    /**
     * The human name for an emergency kind. Lives on the model because the
     * notifier, the handover and the API all have to say the same words.
     */
    public static function kindLabel(?string $kind): string
    {
        return match ($kind) {
            'medical' => 'Medical emergency',
            'accident' => 'Accident',
            'fall' => 'Fall',
            'panic' => 'Panic',
            default => 'Emergency',
        };
    }

    public static function resolutionLabel(?string $key): ?string
    {
        return match ($key) {
            'patient_safe' => 'Patient reached and safe',
            'transported' => 'Transported to a facility',
            'treated_on_site' => 'Treated on site',
            'care_team_handling' => 'Handed to the care team',
            'unreachable' => 'Could not reach the patient',
            'other' => 'Other outcome',
            default => null,
        };
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** Append-only record of how this emergency was worked. */
    public function responseActions(): HasMany
    {
        return $this->hasMany(SosResponseAction::class)->orderBy('created_at');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'kind' => $this->kind,
            'status' => $this->status,
            'resolution' => $this->resolution,
            'resolution_label' => self::resolutionLabel($this->resolution),
            'resolution_note' => $this->resolution_note,
            'location_label' => $this->location_label,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'note' => $this->note,
            'responded_by' => $this->responded_by,
            'triggered_at' => $this->triggered_at?->toIso8601String(),
            'responded_at' => $this->responded_at?->toIso8601String(),
            // Only when already loaded: the SOS lists render hundreds of rows
            // and must not fan out into a query per event.
            'response_actions' => $this->relationLoaded('responseActions')
                ? $this->responseActions->map->toApiArray()->all()
                : [],
        ];
    }
}
