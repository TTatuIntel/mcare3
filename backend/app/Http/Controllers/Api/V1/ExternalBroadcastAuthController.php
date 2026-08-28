<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ExternalAccessToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Authorizes a valid external-access token for its own private Reverb channel.
 * The guest never receives a user/staff channel and the socket carries only
 * the same PHI-free invalidation event used by authenticated clients.
 */
class ExternalBroadcastAuthController extends Controller
{
    public function __invoke(Request $request, string $token): JsonResponse
    {
        $data = $request->validate([
            'socket_id' => ['required', 'string', 'regex:/^\d+\.\d+$/'],
            'channel_name' => ['required', 'string', 'max:120'],
        ]);

        $access = ExternalAccessToken::query()->where('token', $token)->first();
        if (! $access || ! $access->isValid()) {
            return response()->json(['message' => 'External access is unavailable.'], 404);
        }

        $expectedChannel = 'private-external.'.$access->id;
        if (! hash_equals($expectedChannel, $data['channel_name'])) {
            return response()->json(['message' => 'Channel access denied.'], 403);
        }

        $driver = (string) config('broadcasting.default');
        if (! in_array($driver, ['reverb', 'pusher'], true)) {
            return response()->json(['message' => 'Realtime is unavailable.'], 503);
        }

        $connection = config("broadcasting.connections.{$driver}", []);
        $key = is_array($connection) ? ($connection['key'] ?? null) : null;
        $secret = is_array($connection) ? ($connection['secret'] ?? null) : null;
        if (! is_string($key) || $key === '' || ! is_string($secret) || $secret === '') {
            return response()->json(['message' => 'Realtime is unavailable.'], 503);
        }

        $signature = hash_hmac(
            'sha256',
            $data['socket_id'].':'.$data['channel_name'],
            $secret,
        );

        return response()->json(['auth' => $key.':'.$signature]);
    }
}
