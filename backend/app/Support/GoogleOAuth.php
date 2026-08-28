<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

/**
 * Google OAuth 2.0 authorization-code flow for Flutter web (full-page redirect).
 */
class GoogleOAuth
{
    public static function redirectUri(): string
    {
        return (string) config('services.google.redirect_uri');
    }

    public static function buildAuthorizeUrl(
        string $returnTo,
        bool $createAccount,
        bool $remember = false,
        ?string $deviceName = null,
    ): string
    {
        $state = Str::random(48);
        Cache::put("google_oauth:{$state}", [
            'return_to' => $returnTo,
            'create_account' => $createAccount,
            'remember' => $remember,
            'device_name' => $deviceName,
        ], now()->addMinutes(10));

        $query = http_build_query([
            'client_id' => config('services.google.client_id'),
            'redirect_uri' => self::redirectUri(),
            'response_type' => 'code',
            'scope' => 'openid email profile',
            'state' => $state,
            'prompt' => 'select_account',
            'access_type' => 'online',
        ]);

        return 'https://accounts.google.com/o/oauth2/v2/auth?'.$query;
    }

  /**
   * @return array<string, mixed>|null
   */
    public static function exchangeCode(string $code): ?array
    {
        $response = Http::asForm()->timeout(15)->post('https://oauth2.googleapis.com/token', [
            'code' => $code,
            'client_id' => config('services.google.client_id'),
            'client_secret' => config('services.google.client_secret'),
            'redirect_uri' => self::redirectUri(),
            'grant_type' => 'authorization_code',
        ]);

        if (! $response->successful()) {
            return null;
        }

        $json = $response->json();

        return is_array($json) ? $json : null;
    }

    public static function isAllowedReturnTo(string $url): bool
    {
        $parts = parse_url($url);
        if (! is_array($parts)) {
            return false;
        }

        $scheme = strtolower((string) ($parts['scheme'] ?? ''));
        if (! in_array($scheme, ['http', 'https'], true)) {
            return false;
        }

        $host = strtolower((string) ($parts['host'] ?? ''));
        $allowed = array_filter(array_map(
            'trim',
            explode(',', (string) env('MCARE_ALLOWED_RETURN_HOSTS', 'localhost,127.0.0.1')),
        ));

        return in_array($host, $allowed, true);
    }
}
