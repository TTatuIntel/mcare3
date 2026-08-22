<?php

namespace App\Http\Resources;

use App\Models\VitalReading;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * README §4.2 — replaces VitalReading::toApiArray() in HTTP responses.
 * Both `vital` and `vital_key` are emitted for backwards compatibility with
 * the Flutter client's dual parser; keep both until a Flutter release drops
 * the deprecated `vital` field.
 */
class VitalReadingResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var VitalReading $model */
        $model = $this->resource;

        return [
            'id' => (string) $model->id,
            'vital' => $model->vital_key,
            'vital_key' => $model->vital_key,
            'value' => $model->value,
            'secondary_value' => $model->secondary_value,
            'display_value' => $model->displayValue(),
            'risk' => $model->risk,
            'recorded_at' => $model->recorded_at?->toIso8601String(),
            'note' => $model->note,
        ];
    }
}
