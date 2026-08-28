<?php

namespace App\Support;

use App\Services\FcmPushService;
use Illuminate\Support\Facades\DB;

final class ProductionReadiness
{
    /**
     * Fast, read-only checks suitable for a load-balancer readiness probe.
     *
     * @return array{ready: bool, checks: array<string, array{ok: bool, detail: string}>}
     */
    public static function runtime(): array
    {
        $checks = [];

        try {
            DB::select('select 1');
            $checks['database'] = ['ok' => true, 'detail' => 'reachable'];
        } catch (\Throwable) {
            $checks['database'] = ['ok' => false, 'detail' => 'unreachable'];
        }

        $storageReady = is_dir(storage_path()) && is_writable(storage_path());
        $checks['storage'] = [
            'ok' => $storageReady,
            'detail' => $storageReady ? 'writable' : 'not writable',
        ];

        $cacheStore = (string) config('cache.default');
        $checks['cache'] = [
            'ok' => ! in_array($cacheStore, ['array', 'null'], true),
            'detail' => $cacheStore,
        ];

        return [
            'ready' => collect($checks)->every(fn (array $check) => $check['ok']),
            'checks' => $checks,
        ];
    }

    /**
     * Secret-free production configuration audit.
     *
     * @return list<array{gate: string, status: string, detail: string}>
     */
    public static function audit(): array
    {
        $checks = [];
        $add = static function (string $gate, string $status, string $detail) use (&$checks): void {
            $checks[] = compact('gate', 'status', 'detail');
        };

        $add('environment', app()->environment('production') ? 'pass' : 'warn',
            app()->environment('production') ? 'production' : 'APP_ENV is not production');
        $add('debug', config('app.debug') ? 'fail' : 'pass',
            config('app.debug') ? 'APP_DEBUG must be false' : 'disabled');

        $appUrl = (string) config('app.url');
        $frontendUrl = (string) config('mcare.frontend_url');
        $secureUrls = str_starts_with($appUrl, 'https://') && str_starts_with($frontendUrl, 'https://');
        $add('https', $secureUrls ? 'pass' : 'warn',
            $secureUrls ? 'API and frontend use HTTPS' : 'APP_URL and FRONTEND_URL must use HTTPS');
        $add('app-key', filled(config('app.key')) ? 'pass' : 'fail',
            filled(config('app.key')) ? 'configured' : 'APP_KEY is missing');
        $add('mock-social-login', config('mcare.allow_mock_social_login') ? 'fail' : 'pass',
            config('mcare.allow_mock_social_login') ? 'must be disabled' : 'disabled');
        $add('demo-seed', config('mcare.allow_demo_seed') ? 'fail' : 'pass',
            config('mcare.allow_demo_seed') ? 'MCARE_ALLOW_DEMO_SEED must be false' : 'production guard enabled');

        $runtime = self::runtime();
        foreach ($runtime['checks'] as $name => $result) {
            $add($name, $result['ok'] ? 'pass' : 'fail', $result['detail']);
        }

        $queue = (string) config('queue.default');
        $add('queue', match ($queue) {
            'redis', 'sqs' => 'pass',
            'sync', 'null' => 'fail',
            default => 'warn',
        }, "driver: {$queue}");

        $session = (string) config('session.driver');
        $add('session', in_array($session, ['redis', 'memcached'], true) ? 'pass' : 'warn',
            "driver: {$session}; Redis is recommended for multi-instance production");

        $broadcaster = (string) config('broadcasting.default');
        $broadcastConfig = config("broadcasting.connections.{$broadcaster}", []);
        $broadcastReady = in_array($broadcaster, ['reverb', 'pusher'], true)
            && filled($broadcastConfig['key'] ?? null)
            && filled($broadcastConfig['secret'] ?? null)
            && filled($broadcastConfig['app_id'] ?? null);
        $add('realtime', $broadcastReady ? 'pass' : 'fail',
            $broadcastReady ? "{$broadcaster} configured" : 'Reverb or Pusher credentials are incomplete');

        $mailer = (string) config('mail.default');
        $mailReady = ! in_array($mailer, ['log', 'array', 'null'], true)
            && filled(config('mail.from.address'));
        $add('email', $mailReady ? 'pass' : 'fail',
            $mailReady ? "mailer: {$mailer}" : 'configure a transactional mailer and from address');

        $disk = (string) config('filesystems.default');
        $s3 = config('filesystems.disks.s3', []);
        $objectStorageReady = $disk === 's3'
            && filled($s3['key'] ?? null)
            && filled($s3['secret'] ?? null)
            && filled($s3['bucket'] ?? null);
        $add('object-storage', $objectStorageReady ? 'pass' : 'warn',
            $objectStorageReady ? 'S3 configured' : "driver: {$disk}; durable object storage is recommended");

        $add('push', FcmPushService::isV1Configured() ? 'pass' : 'fail',
            FcmPushService::isV1Configured() ? 'FCM HTTP v1 configured' : 'FCM project and readable service account required');

        $googleReady = filled(config('services.google.client_id'))
            && filled(config('services.google.client_secret'))
            && filled(config('services.google.redirect_uri'));
        $add('google-auth', $googleReady ? 'pass' : 'fail',
            $googleReady ? 'configured' : 'OAuth client, secret, or redirect URI missing');
        $add('apple-auth', filled(config('services.apple.client_id')) ? 'pass' : 'fail',
            filled(config('services.apple.client_id')) ? 'allowed audience(s) configured' : 'APPLE_CLIENT_ID missing');

        $requiredExtensions = ['curl', 'json', 'mbstring', 'openssl', 'pdo'];
        $missingExtensions = array_values(array_filter(
            $requiredExtensions,
            fn (string $extension) => ! extension_loaded($extension),
        ));
        $add('php-extensions', $missingExtensions === [] ? 'pass' : 'fail',
            $missingExtensions === [] ? 'required extensions loaded' : 'missing: '.implode(', ', $missingExtensions));

        return $checks;
    }
}
