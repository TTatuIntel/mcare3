<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One step a responder took while working an emergency.
 *
 * Append-only by design: the trail is evidence of how an emergency was
 * handled, so nothing here is edited or deleted while the event lives.
 */
class SosResponseAction extends Model
{
    protected $fillable = [
        'sos_event_id',
        'user_id',
        'actor_name',
        'action',
        'detail',
    ];

    /** The steps a responder can record. */
    public const ACTIONS = [
        'opened_response',
        'called_patient',
        'viewed_location',
        'opened_chart',
        'assigned_provider',
        'took_ownership',
        'note',
    ];

    public static function labelFor(string $action): string
    {
        return match ($action) {
            'opened_response' => 'Opened the response',
            'called_patient' => 'Called the patient',
            'viewed_location' => 'Opened the location',
            'opened_chart' => 'Reviewed the chart',
            'assigned_provider' => 'Handed over to a provider',
            'took_ownership' => 'Took ownership',
            default => 'Note',
        };
    }

    public function event(): BelongsTo
    {
        return $this->belongsTo(SosEvent::class, 'sos_event_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'action' => $this->action,
            'label' => self::labelFor($this->action),
            'detail' => $this->detail,
            'actor_name' => $this->actor_name,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
