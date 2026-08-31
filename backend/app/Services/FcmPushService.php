<?php

namespace App\Services;

use App\Models\CareAssignment;
use App\Models\FcmToken;
use App\Models\SystemSetting;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Delivers Firebase Cloud Messaging pushes. Supports:
 * Uses Firebase HTTP v1 with a service account. The retired legacy server-key
 * API is deliberately not treated as configured.
 */
class FcmPushService
{
    public static function isConfigured(): bool
    {
        return self::isV1Configured();
    }

    public static function isV1Configured(): bool
    {
        return self::configurationIssue() === null;
    }

    public static function configurationIssue(): ?string
    {
        $projectId = (string) config('services.fcm.project_id');
        if (! preg_match('/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/', $projectId)) {
            return 'FCM_PROJECT_ID is missing or invalid';
        }

        $serviceAccount = self::serviceAccount();
        if ($serviceAccount === null) {
            return 'service-account JSON is missing or unreadable';
        }
        if (! hash_equals($projectId, (string) $serviceAccount['project_id'])) {
            return 'service-account project does not match FCM_PROJECT_ID';
        }

        return null;
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
        if (! self::isConfigured() || $userIds === [] || ! self::platformPushEnabled()) {
            return;
        }

        $kind = (string) ($data['kind'] ?? 'general');
        $userIds = self::pushEligibleUserIds($userIds, $kind);
        if ($userIds === []) {
            return;
        }

        $ttlDays = max(1, (int) config('services.fcm.token_ttl_days', 90));
        FcmToken::query()
            ->whereIn('user_id', $userIds)
            ->whereNotNull('last_seen_at')
            ->where('last_seen_at', '<', now()->subDays($ttlDays))
            ->delete();

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

        $kind = (string) ($data['kind'] ?? 'general');
        $data = collect($data)
            ->only([
                'kind',
                'notification_id',
                'patient_id',
                'event_id',
                'alert_id',
                'appointment_id',
                'conversation_id',
                'status',
            ])
            ->map(fn ($v) => is_scalar($v) ? (string) $v : json_encode($v))
            ->all();

        if ((bool) config('services.fcm.redact_notification_content', true)) {
            [$title, $body] = self::privateNotificationCopy($kind);
        }

        foreach (array_chunk($tokens, 500) as $chunk) {
            foreach ($chunk as $token) {
                self::sendV1($token, $title, $body, $data, $priority);
            }
        }
    }

    /** @param list<int|string> $userIds @return list<int> */
    public static function pushEligibleUserIds(array $userIds, string $kind): array
    {
        $preferenceKey = match ($kind) {
            'alert', 'vital_warning', 'vital_critical',
            'sos', 'sos_resolved', 'alert_resolved' => 'vitalAlerts',
            'appointment' => 'appointmentReminders',
            'medication', 'medication_reminder' => 'medicationReminders',
            'message' => 'messages',
            'report', 'report_ready' => 'reports',
            default => null,
        };

        return User::query()
            ->with('settings:user_id,payload')
            ->whereIn('id', $userIds)
            ->get(['id'])
            ->filter(function (User $user) use ($preferenceKey) {
                $notifications = (array) data_get($user->settings?->payload, 'notifications', []);
                if (($notifications['pushEnabled'] ?? true) !== true) {
                    return false;
                }

                return $preferenceKey === null
                    || ($notifications[$preferenceKey] ?? true) === true;
            })
            ->pluck('id')
            ->map(fn ($id) => (int) $id)
            ->values()
            ->all();
    }

    private static function platformPushEnabled(): bool
    {
        $setting = SystemSetting::query()->where('key', 'push_notifications')->value('value');

        return $setting === null || (bool) $setting;
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
                        'channel_id' => $priority === 'high'
                            ? 'sos_emergency'
                            : 'mcare_updates',
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

        $cacheKey = 'fcm_access_token:'.hash(
            'sha256',
            config('services.fcm.project_id').'|'.$sa['client_email'],
        );

        return Cache::remember($cacheKey, 3300, function () use ($sa) {
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
            if (! openssl_sign($unsigned, $signature, $privateKey, OPENSSL_ALGORITHM_SHA256)) {
                return null;
            }
            $jwt = "{$unsigned}.".self::base64Url($signature);

            $response = Http::asForm()
                ->timeout(15)
                ->post('https://oauth2.googleapis.com/token', [
                    'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                    'assertion' => $jwt,
                ]);

            return $response->successful()
                ? $response->json('access_token')
                : null;
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
            || ($json['type'] ?? null) !== 'service_account'
            || ! filled($json['project_id'] ?? null)
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

    /** @return array{0: string, 1: string} */
    private static function privateNotificationCopy(string $kind): array
    {
        return match ($kind) {
            'sos' => [
                'Urgent mCare alert',
                'Open mCare to view and respond to this emergency.',
            ],
            'sos_resolved' => [
                'mCare emergency update',
                'Open mCare to view the latest emergency status.',
            ],
            // The outcome and the clinician's note are clinical detail, so the
            // lock screen says only that there is an answer waiting.
            'alert_resolved' => [
                'mCare alert update',
                'Your care team has reviewed an alert. Open mCare to read it.',
            ],
            default => [
                'New mCare update',
                'Open mCare to securely view this update.',
            ],
        };
    }
}
