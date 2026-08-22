<?php

namespace App\Http\Resources;

use App\Models\MedicalDocument;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class MedicalDocumentResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var MedicalDocument $d */
        $d = $this->resource;

        $hasFile = $d->storage_path
            && Storage::disk('public')->exists($d->storage_path);

        return [
            'id' => (string) $d->id,
            'title' => $d->title,
            'category' => $d->category,
            'file_type' => $d->file_type,
            'size_bytes' => $d->size_bytes,
            'uploaded_at' => $d->uploaded_at?->toIso8601String(),
            'uploaded_by' => $d->uploaded_by,
            'description' => $d->description,
            'shared_with_doctor_id' => $d->shared_with_doctor_id
                ? (string) $d->shared_with_doctor_id
                : null,
            'has_file' => $hasFile,
        ];
    }
}
