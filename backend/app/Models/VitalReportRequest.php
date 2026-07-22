<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VitalReportRequest extends Model
{
    protected $fillable = [
        'user_id',
        'range_from',
        'range_to',
        'vitals',
        'note',
        'status',
        'current_responder',
        'last_escalated_at',
        'responded_at',
        'responded_by',
        'response_note',
    ];

    protected function casts(): array
    {
        return [
            'range_from' => 'date',
            'range_to' => 'date',
            'vitals' => 'array',
            'last_escalated_at' => 'datetime',
            'responded_at' => 'datetime',
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
            'from' => $this->range_from?->toIso8601String(),
            'to' => $this->range_to?->toIso8601String(),
            'vitals' => $this->vitals ?? [],
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'current_responder' => $this->current_responder,
            'note' => $this->note,
            'responded_at' => $this->responded_at?->toIso8601String(),
            'responded_by' => $this->responded_by,
            'response_note' => $this->response_note,
            'last_escalated_at' => $this->last_escalated_at?->toIso8601String(),
        ];
    }
}
