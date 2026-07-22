<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Announcement extends Model
{
    public const AUDIENCES = [
        'all',
        'patients',
        'doctors',
        'healthworkers',
        'mcare_assistant',
        'admin',
    ];

    protected $fillable = [
        'title',
        'body',
        'audience',
        'cta_label',
        'cta_url',
        'image_path',
        'starts_at',
        'ends_at',
        'is_published',
        'created_by_user_id',
    ];

    protected function casts(): array
    {
        return [
            'starts_at' => 'datetime',
            'ends_at' => 'datetime',
            'is_published' => 'boolean',
        ];
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_user_id');
    }

    public function isLive(): bool
    {
        if (! $this->is_published) {
            return false;
        }
        $now = now();
        if ($this->starts_at && $now->lt($this->starts_at)) {
            return false;
        }
        if ($this->ends_at && $now->gt($this->ends_at)) {
            return false;
        }
        return true;
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'title' => $this->title,
            'body' => $this->body,
            'audience' => $this->audience,
            'cta_label' => $this->cta_label,
            'cta_url' => $this->cta_url,
            'image_path' => $this->image_path,
            'starts_at' => $this->starts_at?->toIso8601String(),
            'ends_at' => $this->ends_at?->toIso8601String(),
            'is_published' => $this->is_published,
            'is_live' => $this->isLive(),
            'created_by' => $this->createdBy?->fullName(),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
