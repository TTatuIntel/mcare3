<?php

namespace App\Support;

use App\Services\RealtimeSignalService;
use Illuminate\Http\Request;

/**
 * Where a client should point its WebSocket, decided by the server.
 *
 * The app used to learn this from `--dart-define` at build time, which meant
 * real-time was only on for builds whose launch command happened to carry two
 * flags. Every other build — an IDE run, a plain `flutter build web`, the one
 * a tester installed — silently ran with no socket at all and fell back to
 * polling, which is exactly the "I have to refresh" behaviour.
 *
 * The API knows its own broadcaster, so it says. Only public values leave:
 * the Reverb *app key* is published to every browser that connects, the same
 * as any Pusher key. The app *secret* and app id never appear here.
 *
 * The host is the interesting part. `REVERB_HOST` is usually a bind address
 * (`localhost`, `0.0.0.0`), which is meaningless to a phone on the same LAN
 * reading this over `http://192.168.1.20:8000`. When it is a loopback or
 * wildcard we answer with the host the client already reached us on, so the
 * socket lands wherever the API did.
 */
final class RealtimeEndpoint
{
    private const LOCAL_HOSTS = ['localhost', '127.0.0.1', '0.0.0.0', '::', '[::]'];

    /** @return array{enabled: bool, url: string, key: string} */
    public static function describe(Request $request): array
    {
        if (! RealtimeSignalService::enabled()) {
            return ['enabled' => false, 'url' => '', 'key' => ''];
        }

        $driver = (string) config('broadcasting.default');
        $connection = (array) config("broadcasting.connections.{$driver}", []);
        $key = (string) ($connection['key'] ?? '');
        $options = (array) ($connection['options'] ?? []);

        $scheme = strtolower((string) ($options['scheme'] ?? 'https')) === 'https' ? 'wss' : 'ws';
        $host = trim((string) ($options['host'] ?? ''));
        $port = (int) ($options['port'] ?? 0);

        if ($host === '' || in_array($host, self::LOCAL_HOSTS, true)) {
            $host = $request->getHost();
        }

        if ($key === '' || $host === '') {
            return ['enabled' => false, 'url' => '', 'key' => ''];
        }

        // A socket served through the standard web port needs no port in the
        // URL; anything else does, because Reverb listens beside the API.
        $isDefaultPort = ($scheme === 'wss' && $port === 443)
            || ($scheme === 'ws' && $port === 80)
            || $port <= 0;

        $authority = str_contains($host, ':') && ! str_starts_with($host, '[')
            ? '['.$host.']'   // bare IPv6
            : $host;

        return [
            'enabled' => true,
            'url' => $isDefaultPort ? "{$scheme}://{$authority}" : "{$scheme}://{$authority}:{$port}",
            'key' => $key,
        ];
    }
}
