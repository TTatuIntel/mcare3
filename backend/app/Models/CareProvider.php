<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CareProvider extends Model
{
    protected $fillable = [
        'user_id',
        'name',
        'specialty',
        'facility',
        'years_experience',
        'rating',
        'total_reviews',
        'bio',
        'languages',
    ];

    protected function casts(): array
    {
        return [
            'rating' => 'float',
            'years_experience' => 'integer',
            'total_reviews' => 'integer',
            'languages' => 'array',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function requests(): HasMany
    {
        return $this->hasMany(CareRequest::class, 'provider_id');
    }

    public function assignments(): HasMany
    {
        return $this->hasMany(CareAssignment::class, 'provider_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'name' => $this->name,
            'specialty' => $this->specialty,
            'facility' => $this->facility,
            'years_experience' => $this->years_experience,
            'rating' => $this->rating,
            'total_reviews' => $this->total_reviews,
            'bio' => $this->bio,
            'languages' => $this->languages ?? ['English'],
        ];
    }
}
