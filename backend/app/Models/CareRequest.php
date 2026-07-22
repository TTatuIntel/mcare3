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
        'reason',
        'status',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function provider(): BelongsTo
    {
        return $this->belongsTo(CareProvider::class, 'provider_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'provider_id' => (string) $this->provider_id,
            'provider_name' => $this->provider_name,
            'provider_specialty' => $this->provider_specialty,
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'reason' => $this->reason,
        ];
    }
}
