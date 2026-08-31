<?php

namespace App\Support;

/**
 * Validates only the shape/presence of SMTP configuration.
 *
 * It deliberately never returns a credential value, so readiness endpoints
 * and console diagnostics cannot accidentally expose an API key.
 */
final class MailConfiguration
{
    public static function credentialIssue(?string $mailer = null): ?string
    {
        $mailer ??= (string) config('mail.default');
        if ($mailer !== 'smtp') {
            return null;
        }

        $config = (array) config('mail.mailers.smtp', []);
        if (blank($config['host'] ?? null)) {
            return 'MAIL_HOST is missing';
        }
        if (blank($config['username'] ?? null)) {
            return 'MAIL_USERNAME is missing';
        }

        $password = trim((string) ($config['password'] ?? ''));
        if ($password === '') {
            return 'MAIL_PASSWORD is missing';
        }
        if (self::looksLikePlaceholder($password)) {
            return 'MAIL_PASSWORD is still a placeholder; create a real SMTP API key or app password';
        }

        return null;
    }

    private static function looksLikePlaceholder(string $value): bool
    {
        $normalized = strtoupper(trim($value, " \t\n\r\0\x0B\"'"));

        return str_contains($normalized, 'REPLACE')
            || str_contains($normalized, 'YOUR_')
            || str_contains($normalized, 'PLACEHOLDER')
            || str_contains($normalized, 'CHANGE_ME');
    }
}
