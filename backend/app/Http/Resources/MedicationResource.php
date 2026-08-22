<?php

namespace App\Http\Resources;

use App\Models\Medication;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MedicationResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var Medication $m */
        $m = $this->resource;

        return [
            'id' => (string) $m->id,
            'name' => $m->name,
            'dosage' => $m->dosage,
            'frequency' => $m->frequency,
            'form' => $m->form,
            'instructions' => $m->instructions,
            'prescribed_by' => $m->prescribed_by,
            'start_date' => $m->start_date?->toIso8601String(),
            'end_date' => $m->end_date?->toIso8601String(),
            'expiry_date' => $m->expiry_date?->toIso8601String(),
            'refills_left' => $m->refills_left,
            'source' => $m->source,
            'active' => $m->active,
        ];
    }
}
