<?php

namespace App\Http\Resources;

use App\Models\Appointment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AppointmentResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var Appointment $a */
        $a = $this->resource;

        return [
            'id' => (string) $a->id,
            'doctor_id' => (string) ($a->doctor_user_id ?? ''),
            'doctor_name' => $a->doctor_name,
            'doctor_specialty' => $a->doctor_specialty,
            'scheduled_at' => $a->scheduled_at?->toIso8601String(),
            'duration_minutes' => $a->duration_minutes,
            'type' => $a->type,
            'status' => $a->status,
            'reason' => $a->reason,
            'location_or_link' => $a->location_or_link,
            'cancellation_reason' => $a->cancellation_reason,
        ];
    }
}
