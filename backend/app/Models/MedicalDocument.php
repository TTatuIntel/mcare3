<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class MedicalDocument extends Model
{
    protected $fillable = [
        'user_id',
        'title',
        'category',
        'file_type',
        'storage_path',
        'size_bytes',
        'uploaded_by',
        'description',
        'shared_with_doctor_id',
        'uploaded_at',
    ];

    protected function casts(): array
    {
        return [
            'uploaded_at' => 'datetime',
            'size_bytes' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * The doctor this document has been explicitly shared with, if any.
     */
    public function sharedWithDoctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'shared_with_doctor_id');
    }

    public function toApiArray(): array
    {
        $hasFile = $this->storage_path
            && Storage::disk('public')->exists($this->storage_path);

        return [
            'id' => (string) $this->id,
            'title' => $this->title,
            'category' => $this->category,
            'file_type' => $this->file_type,
            'size_bytes' => $this->size_bytes,
            'uploaded_at' => $this->uploaded_at?->toIso8601String(),
            'uploaded_by' => $this->uploaded_by,
            'description' => $this->description,
            'shared_with_doctor_id' => $this->shared_with_doctor_id
                ? (string) $this->shared_with_doctor_id
                : null,
            'has_file' => $hasFile,
        ];
    }
}
