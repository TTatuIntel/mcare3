<?php

namespace App\Services;

use App\Models\CareAssignment;
use App\Models\FcmToken;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Delivers Firebase Cloud Messaging pushes. Supports:
 * - Legacy server key (FCM_SERVER_KEY) for quick local setup
 * - HTTP v1 via service-account JSON (FCM_SERVICE_ACCOUNT_PATH)
 */
class FcmPushService
{
    public static function isConfigured(): bool
    {
        return filled(config('services.fcm.server_key'))
            || self::serviceAccount() !== null;
    }

    public static function isV1Configured(): bool
    {
        return filled(config('services.fcm.project_id'))
            && self::serviceAccount() !== null;
    }

    /**
     * @param  list<int|string>  $userIds
     */
    public static function sendToUsers(
        array $userIds,
        string $title,
        string $body,
        array $data = [],
        string $priority = 'high',
    ): void {
        if (! self::isConfigured() || $userIds === []) {
            return;
        }

        $tokens = FcmToken::query()
            ->whereIn('user_id', $userIds)
            ->pluck('token')
            ->unique()
            ->values()
            ->all();

        if ($tokens === []) {
            return;
        }

        self::sendToTokens($tokens, $title, $body, $data, $priority);
    }

    /**
     * @param  list<string>  $tokens
     */
    public static function sendToTokens(
        array $tokens,
        string $title,
        string $body,
        array $data = [],
        string $priority = 'high',
    ): void {
        if (! self::isConfigured() || $tokens === []) {
            return;
        }

        $data = collect($data)
            ->map(fn ($v) => is_scalar($v) ? (string) $v : json_encode($v))
            ->all();

        if (self::serviceAccount() !== null) {
            foreach (array_chunk($tokens, 500) as $chunk) {
                foreach ($chunk as $token) {
                    self::sendV1($token, $title, $body, $data, $priority);
                }
            }

            return;
        }

        foreach (array_chunk($tokens, 1000) as $chunk) {
            self::sendLegacy($chunk, $title, $body, $data, $priority);
        }
    }

    /**
     * Doctors assigned to the patient + platform admins/assistants.
     *
     * @return list<int>
     */
    public static function sosRecipientUserIds(int $patientUserId): array
    {
        $doctorIds = CareAssignment::query()
            ->where('patient_user_id', $patientUserId)
            ->whereNull('ended_at')
            ->with('provider:id,user_id')
            ->get()
            ->toBase()
            ->map(fn (CareAssignment $a) => $a->provider?->user_id)
            ->filter()
            ->values();

        $staffIds = User::query()
            ->whereIn('role', ['admin', 'mcare_assistant'])
            ->pluck('id');

        return $doctorIds
            ->merge($staffIds)
            ->unique()
            ->map(fn ($id) => (int) $id)
            ->values()
            ->all();
    }

    /**
     * @param  list<string>  $tokens
     */
    private static function sendLegacy(
        array $tokens,
        string $title,
        string $body,
        array $data,
        string $priority,
    ): void {
        $key = config('services.fcm.server_key');
        if (! $key) {
            return;
        }

        try {
            $response = Http::withHeaders([
                'Authorization' => 'key='.$key,
                'Content-Type' => 'application/json',
            ])->post('https://fcm.googleapis.com/fcm/send', [
                'registration_ids' => $tokens,
                'priority' => $priority,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                    'sound' => 'default',
                ],
                'data' => $data,
            ]);

            if (! $response->successful()) {
                Log::warning('FCM legacy push failed', [
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('FCM legacy push error', ['message' => $e->getMessage()]);
        }
    }

    private static function sendV1(
        string $token,
        string $title,
        string $body,
        array $data,
        string $priority,
    ): void {
        $accessToken = self::accessToken();
        $projectId = config('services.fcm.project_id');
        if (! $accessToken || ! $projectId) {
            return;
        }

        $payload = [
            'message' => [
                'token' => $token,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $data,
                'android' => [
                    'priority' => $priority === 'high' ? 'HIGH' : 'NORMAL',
                    'notification' => [
                        'channel_id' => 'sos_emergency',
                        'sound' => 'default',
                    ],
                ],
                'apns' => [
                    'headers' => [
                        'apns-priority' => $priority === 'high' ? '10' : '5',
                    ],
                    'payload' => [
                        'aps' => [
                            'sound' => 'default',
                        ],
                    ],
                ],
                'webpush' => [
                    'headers' => [
                        'Urgency' => $priority === 'high' ? 'high' : 'normal',
                    ],
                ],
            ],
        ];

        try {
            $response = Http::withToken($accessToken)
                ->post(
                    "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send",
                    $payload,
                );

            if (! $response->successful()) {
                if (self::isPermanentTokenFailure($response->status(), $response->json())) {
                    FcmToken::query()->where('token', $token)->delete();
                }
                Log::warning('FCM v1 push failed', [
                    'status' => $response->status(),
                    'reason' => (string) ($response->json('error.status') ?? 'unknown'),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('FCM v1 push error', ['message' => $e->getMessage()]);
        }
    }

    private static function accessToken(): ?string
    {
        $sa = self::serviceAccount();
        if (! $sa) {
            return null;
        }

        return Cache::remember('fcm_access_token', 3300, function () use ($sa) {
            $now = time();
            $header = self::base64Url(json_encode([
                'alg' => 'RS256',
                'typ' => 'JWT',
            ]));
            $claim = self::base64Url(json_encode([
                'iss' => $sa['client_email'],
                'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                'aud' => 'https://oauth2.googleapis.com/token',
                'iat' => $now,
                'exp' => $now + 3600,
            ]));
            $unsigned = "{$header}.{$claim}";

            $privateKey = openssl_pkey_get_private($sa['private_key']);
            if (! $privateKey) {
                return null;
            }

            $signature = '';
            openssl_sign($unsigned, $signature, $privateKey, OPENSSL_ALGORITHM_SHA256);
            $jwt = "{$unsigned}.".self::base64Url($signature);

            $response = Http::asForm()->post('https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]);

            return $response->json('access_token');
        });
    }

    private static function serviceAccount(): ?array
    {
        $path = config('services.fcm.service_account_path');
        if (! $path) {
            return null;
        }

        if (! str_starts_with($path, '/') && ! preg_match('/^[A-Za-z]:[\\\\\/]/', $path)) {
            $path = base_path($path);
        }
        if (! is_readable($path)) {
            return null;
        }

        $json = json_decode((string) file_get_contents($path), true);

        if (! is_array($json)
            || ! filled($json['client_email'] ?? null)
            || ! filled($json['private_key'] ?? null)) {
            return null;
        }

        return $json;
    }

    private static function isPermanentTokenFailure(int $status, mixed $body): bool
    {
        if (! is_array($body)) {
            $body = [];
        }
        $reason = (string) data_get($body, 'error.status', '');
        $details = collect(data_get($body, 'error.details', []));
        $fcmDetail = $details->first(
            fn ($detail) => is_array($detail) && isset($detail['errorCode']),
        );
        $fcmCode = is_array($fcmDetail) ? ($fcmDetail['errorCode'] ?? null) : null;

        return $status === 404
            || $reason === 'NOT_FOUND'
            || $fcmCode === 'UNREGISTERED';
    }

    private static function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
