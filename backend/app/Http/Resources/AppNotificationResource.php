<?php

namespace App\Http\Resources;

use App\Models\AppNotification;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * README §4.2 — replaces AppNotification::toApiArray() in HTTP responses.
 * Shape is byte-identical to the previous array; verified by
 * ResponseShapeParityTest.
 */
class AppNotificationResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var AppNotification $model */
        $model = $this->resource;

        return [
            'id' => (string) $model->id,
            'kind' => $model->kind,
            'title' => $model->title,
            'body' => $model->body,
            'action_route' => $model->action_route,
            'action_arguments' => $model->action_arguments,
            'read' => $model->read,
            'resolved' => $model->resolved,
            'resolved_at' => $model->resolved_at?->toIso8601String(),
            'created_at' => $model->created_at?->toIso8601String(),
        ];
    }
}
