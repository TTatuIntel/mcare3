<?php

namespace App\Support;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Verifies Google ID tokens issued to our OAuth web client.
 *
 * @see https://developers.google.com/identity/sign-in/web/backend-auth
 */
class GoogleIdTokenVerifier
{
    public function verify(string $idToken): ?array
    {
        $clientId = config('services.google.client_id');
        if (! $clientId) {
            Log::warning('GOOGLE_CLIENT_ID is not configured.');

            return null;
        }

        try {
            $response = Http::timeout(12)->get(
                'https://oauth2.googleapis.com/tokeninfo',
                ['id_token' => $idToken],
            );

            if (! $response->successful()) {
                return null;
            }

            $payload = $response->json();
            if (! is_array($payload)) {
                return null;
            }

            if (($payload['aud'] ?? '') !== $clientId) {
                Log::warning('Google token audience mismatch.', [
                    'aud' => $payload['aud'] ?? null,
                ]);

                return null;
            }

            $verified = $payload['email_verified'] ?? false;
            if ($verified !== true && $verified !== 'true') {
                return null;
            }

            if (empty($payload['email']) || empty($payload['sub'])) {
                return null;
            }

            return $payload;
        } catch (\Throwable $e) {
            Log::error('Google ID token verification failed.', [
                'message' => $e->getMessage(),
            ]);

            return null;
        }
    }
}
