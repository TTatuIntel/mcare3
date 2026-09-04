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

    /**
     * Resolve the care_providers row for a directory user id, creating it on
     * first use. Admin screens identify doctors by their user id, while every
     * caseload gate (DoctorAccess) keys off care_providers.
     */
    public static function resolveForUser(int|string $userId): self
    {
        $user = User::find($userId);

        // `users.specialty` is nullable but `care_providers.specialty` is not,
        // so a doctor who never filled in a specialty used to blow this up with
        // a NOT NULL violation — surfacing as a 500 on the admin's "route this
        // request" action. Fall back to a neutral label instead.
        $specialty = trim((string) ($user?->specialty ?? ''));

        return static::updateOrCreate(
            ['user_id' => $userId],
            [
                'name' => $user?->fullName() ?? 'Care Provider',
                'specialty' => $specialty !== '' ? $specialty : 'General practice',
            ],
        );
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
            // The directory user behind the provider row. Every staff-facing
            // surface addresses clinicians by user id, so a payload that only
            // carries the care_providers id cannot name one — which is what
            // a patient asking a specific doctor for a document has to do.
            'user_id' => $this->user_id ? (string) $this->user_id : null,
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
