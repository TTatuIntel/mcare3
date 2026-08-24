<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CareRequest extends Model
{
    protected $fillable = [
        'user_id',
        'provider_id',
        'provider_name',
        'provider_specialty',
        'assigned_provider_id',
        'assignment_role',
        'reason',
        'decision_note',
        'status',
        'decided_by',
        'decided_at',
    ];

    protected function casts(): array
    {
        return [
            'decided_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function provider(): BelongsTo
    {
        return $this->belongsTo(CareProvider::class, 'provider_id');
    }

    /** Provider the admin actually routed the patient to. */
    public function assignedProvider(): BelongsTo
    {
        return $this->belongsTo(CareProvider::class, 'assigned_provider_id');
    }

    public function decider(): BelongsTo
    {
        return $this->belongsTo(User::class, 'decided_by');
    }

    /**
     * True when the admin approved the request with a provider other than the
     * one the patient asked for.
     */
    public function wasReassigned(): bool
    {
        return $this->assigned_provider_id !== null
            && (int) $this->assigned_provider_id !== (int) $this->provider_id;
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'patient_id' => (string) $this->user_id,
            'provider_id' => (string) $this->provider_id,
            'provider_name' => $this->provider_name,
            'provider_specialty' => $this->provider_specialty,
            'assigned_provider_id' => $this->assigned_provider_id === null
                ? null
                : (string) $this->assigned_provider_id,
            'assigned_provider_name' => $this->assignedProvider?->name,
            'assignment_role' => $this->assignment_role,
            'reassigned' => $this->wasReassigned(),
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'reason' => $this->reason,
            'decision_note' => $this->decision_note,
            'decided_at' => $this->decided_at?->toIso8601String(),
            'decided_by_name' => $this->decider?->fullName(),
        ];
    }
}
