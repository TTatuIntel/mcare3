<?php

namespace App\Http\Resources;

use App\Models\MedicalDocument;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The patient-facing wrapper around a document.
 *
 * It used to carry its own copy of the field list, which meant every document
 * in the system had two independent serialisers: this one for the patient's own
 * routes and {@see MedicalDocument::toApiArray()} for the staff and session
 * ones. They were identical on the day the second was written and had already
 * started to drift — a field added for the doctor's chart simply did not exist
 * for the patient looking at the same row. There is now one shape, defined on
 * the model, and this exists to keep collection-mapping ergonomics at the call
 * sites that want them.
 */
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

<<<<<<< Updated upstream
        $hasFile = MedicalDocumentFiles::exists($d->storage_path);

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
=======
        return $d->toApiArray();
>>>>>>> Stashed changes
    }
}
