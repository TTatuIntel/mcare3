<?php

namespace App\Http\Resources;

use App\Models\MedicationDose;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MedicationDoseResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var MedicationDose $d */
        $d = $this->resource;

        return [
            'id' => (string) $d->id,
            'medication_id' => (string) $d->medication_id,
            'scheduled_at' => $d->scheduled_at?->toIso8601String(),
            'taken_at' => $d->taken_at?->toIso8601String(),
            'status' => $d->status,
        ];
    }
}
