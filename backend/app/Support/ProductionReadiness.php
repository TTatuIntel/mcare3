<?php

namespace App\Support;

use App\Services\FcmPushService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\Mailer\Transport\Smtp\EsmtpTransport;

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
        if (! $mailReady) {
            $add('email', 'fail', 'configure a transactional mailer and from address');
        } else {
            // Configuration being present says nothing about the provider
            // accepting mail. A daily sending cap silently rejected every
            // message for a day while this gate read "pass", because every
            // caller reports mail failures and carries on. Ask the transport.
            [$ok, $detail] = self::probeMailTransport();

            // The probe stops at AUTH, and a consumer mailbox answers AUTH long
            // after it has stopped accepting messages: Gmail caps a free account
            // at a few hundred a day, then rejects every send at DATA with
            // "550-5.4.5 Daily user sending limit exceeded" while the login keeps
            // working. This gate read PASS through exactly that outage. Passing
            // credentials are necessary and not sufficient, so a relay that is
            // not a transactional provider can never be more than a warning.
            $host = (string) config("mail.mailers.{$mailer}.host", '');
            $consumerRelay = (bool) preg_match('/(^|\.)(gmail|googlemail|yahoo|outlook|hotmail|live|aol|icloud)\./i', $host);

            if (! $ok) {
                $add('email', 'fail', "mailer: {$mailer}; {$detail}");
            } elseif ($consumerRelay) {
                $add('email', 'warn', "mailer: {$mailer}; {$host} is a consumer mailbox with a daily "
                    .'sending cap, not a transactional provider — use Resend, SES or Postmark. '
                    .'Prove delivery with: php artisan mcare:mail-test <address>');
            } else {
                $add('email', 'pass', "mailer: {$mailer}; {$detail} (credentials only — "
                    .'confirm delivery with: php artisan mcare:mail-test <address>)');
            }
        }

        $smsDriver = (string) config('services.sms.driver', 'log');
        $smsReady = $smsDriver === 'twilio'
            && filled(config('services.sms.twilio.sid'))
            && filled(config('services.sms.twilio.token'))
            && filled(config('services.sms.twilio.from'))
            && filled(config('services.sms.default_country_code'));
        $add('sms-recovery', $smsReady ? 'pass' : 'fail',
            $smsReady ? 'Twilio and default country code configured' : 'configure Twilio and SMS_DEFAULT_COUNTRY_CODE');

        $disk = (string) config('filesystems.default');
        $s3 = config('filesystems.disks.s3', []);
        $objectStorageReady = $disk === 's3'
            && filled($s3['key'] ?? null)
            && filled($s3['secret'] ?? null)
            && filled($s3['bucket'] ?? null);
        $add('object-storage', $objectStorageReady ? 'pass' : 'warn',
            $objectStorageReady ? 'S3 configured' : "driver: {$disk}; durable object storage is recommended");

        $pushIssue = FcmPushService::configurationIssue();
        $add('push', $pushIssue === null ? 'pass' : 'fail',
            $pushIssue === null ? 'FCM HTTP v1 configured' : $pushIssue);

        $database = config('database.connections.'.config('database.default'), []);
        $databaseUser = (string) ($database['username'] ?? '');
        $databaseHost = (string) ($database['host'] ?? '');
        $databasePassword = (string) ($database['password'] ?? '');
        $localDatabase = in_array($databaseHost, ['127.0.0.1', 'localhost', '::1'], true);
        $leastPrivilege = $databaseUser !== ''
            && strtolower($databaseUser) !== 'root'
            && $databasePassword !== '';
        $tlsConfigured = $localDatabase || ! empty($database['options'] ?? []);
        $databaseSecure = $leastPrivilege && $tlsConfigured;
        $add('database-security', $databaseSecure ? 'pass' : 'warn',
            $databaseSecure
                ? 'dedicated credential and transport policy configured'
                : 'use a non-root passworded user and a CA for remote MySQL');

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

    /**
     * Connects and authenticates against the configured SMTP server without
     * sending anything, so a rejected credential or an exhausted sending quota
     * surfaces here instead of in a swallowed exception.
     *
     * @return array{0: bool, 1: string}
     */
    private static function probeMailTransport(): array
    {
        if ((string) config('mail.default') !== 'smtp') {
            return [true, 'transport not probed (non-SMTP)'];
        }

        $configurationIssue = MailConfiguration::credentialIssue('smtp');
        if ($configurationIssue !== null) {
            return [false, $configurationIssue];
        }

        $config = config('mail.mailers.smtp', []);
        $host = (string) ($config['host'] ?? '');
        if ($host === '') {
            return [false, 'MAIL_HOST is missing'];
        }

        try {
            $transport = new EsmtpTransport(
                $host,
                (int) ($config['port'] ?? 587),
                ($config['scheme'] ?? null) === 'smtps',
            );
            if (filled($config['username'] ?? null)) {
                $transport->setUsername((string) $config['username']);
                $transport->setPassword((string) ($config['password'] ?? ''));
            }
            if (filled($config['local_domain'] ?? null)) {
                $transport->setLocalDomain((string) $config['local_domain']);
            }
            $stream = $transport->getStream();
            if (method_exists($stream, 'setTimeout')) {
                $stream->setTimeout(5);
            }
            $transport->start();
            $transport->stop();

            return [true, 'transport accepted credentials'];
        } catch (\Throwable $e) {
            return [false, 'transport refused: '.Str::limit(
                str_replace(['
', '
'], ' ', $e->getMessage()),
                160,
            )];
        }
    }
}
