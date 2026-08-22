<?php

namespace App\Http\Resources;

use App\Models\SosEvent;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SosEventResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var SosEvent $e */
        $e = $this->resource;

        return [
            'id' => (string) $e->id,
            'kind' => $e->kind,
            'status' => $e->status,
            'location_label' => $e->location_label,
            'latitude' => $e->latitude,
            'longitude' => $e->longitude,
            'note' => $e->note,
            'responded_by' => $e->responded_by,
            'triggered_at' => $e->triggered_at?->toIso8601String(),
            'responded_at' => $e->responded_at?->toIso8601String(),
        ];
    }
}
