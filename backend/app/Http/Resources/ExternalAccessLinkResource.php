<?php

namespace App\Http\Resources;

use App\Models\ExternalAccessToken;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * README §4.2 — replaces the private toApiArray helper on
 * PatientExternalAccessController. The `url` field is composed here so the
 * controller no longer knows the frontend host layout.
 */
class ExternalAccessLinkResource extends JsonResource
{
    public static $wrap = null;

    /**
     * @param  Request  $request
     * @return array<string, mixed>
     */
    public function toArray($request): array
    {
        /** @var ExternalAccessToken $model */
        $model = $this->resource;

        $frontend = rtrim((string) config('mcare.frontend_url', ''), '/');

        return [
            'id' => (string) $model->id,
            'label' => $model->label,
            'access_code' => $model->access_code,
            'url' => $frontend !== '' ? $frontend.'/external?token='.$model->token : null,
            'token' => $model->token,
            'expires_at' => $model->expires_at->toIso8601String(),
            'revoked_at' => $model->revoked_at?->toIso8601String(),
            'active' => $model->isValid(),
            'created_at' => $model->created_at?->toIso8601String(),
        ];
    }
}
