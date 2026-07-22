<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ClinicalReport extends Model
{
    protected $fillable = [
        'patient_user_id',
        'author_user_id',
        'title',
        'body',
        'published',
        'published_at',
    ];

    protected function casts(): array
    {
        return [
            'published' => 'boolean',
            'published_at' => 'datetime',
        ];
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'patient_user_id');
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_user_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'patient_user_id' => (string) $this->patient_user_id,
            'title' => $this->title,
            'body' => $this->body,
            'published' => $this->published,
            'published_at' => $this->published_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
