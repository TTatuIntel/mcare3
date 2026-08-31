<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Verifies "Sign in with Apple" identity tokens.
 *
 * Apple issues an RS256-signed JWT and — unlike Google — offers no
 * `tokeninfo` endpoint, so we verify the signature locally against Apple's
 * published JWKS (https://appleid.apple.com/auth/keys) and validate the
 * standard claims (iss / aud / exp). No third-party JWT package is required;
 * the JWK → PEM conversion and RS256 check use only ext-openssl.
 *
 * @see https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/verifying_a_user
 */
class AppleIdTokenVerifier
{
    private const ISSUER = 'https://appleid.apple.com';

    private const JWKS_URL = 'https://appleid.apple.com/auth/keys';

    private const JWKS_CACHE_KEY = 'apple_jwks';

    /**
     * Returns the decoded token claims when valid, otherwise null.
     *
     * @return array<string, mixed>|null
     */
    public function verify(string $identityToken, ?string $expectedNonceHash = null): ?array
    {
        $allowedAudiences = $this->allowedAudiences();
        if ($allowedAudiences === []) {
            Log::warning('APPLE_CLIENT_ID is not configured.');

            return null;
        }

        try {
            [$headerB64, $payloadB64, $signatureB64] = $this->split($identityToken);

            $header = json_decode($this->b64urlDecode($headerB64), true);
            $payload = json_decode($this->b64urlDecode($payloadB64), true);
            if (! is_array($header) || ! is_array($payload)) {
                return null;
            }

            $pem = $this->pemForKid((string) ($header['kid'] ?? ''));
            if ($pem === null) {
                return null;
            }

            $signed = $headerB64.'.'.$payloadB64;
            $signature = $this->b64urlDecode($signatureB64);
            $ok = openssl_verify($signed, $signature, $pem, OPENSSL_ALGO_SHA256);
            if ($ok !== 1) {
                Log::warning('Apple identity token signature check failed.');

                return null;
            }

            if (($payload['iss'] ?? '') !== self::ISSUER) {
                return null;
            }
            if (! in_array((string) ($payload['aud'] ?? ''), $allowedAudiences, true)) {
                Log::warning('Apple token audience mismatch.', ['aud' => $payload['aud'] ?? null]);

                return null;
            }
            if ((int) ($payload['exp'] ?? 0) < time()) {
                return null;
            }
            if (empty($payload['sub'])) {
                return null;
            }
            if ($expectedNonceHash !== null) {
                $tokenNonce = (string) ($payload['nonce'] ?? '');
                // Apple clients may place the raw nonce or its SHA-256 value
                // in the claim. Bind either form to the one-time server
                // challenge without ever storing the raw nonce server-side.
                $nonceMatches = $tokenNonce !== ''
                    && (hash_equals($expectedNonceHash, hash('sha256', $tokenNonce))
                        || hash_equals($expectedNonceHash, $tokenNonce));
                if (! $nonceMatches) {
                    Log::warning('Apple token nonce mismatch.');

                    return null;
                }
            }

            return $payload;
        } catch (\Throwable $e) {
            Log::error('Apple identity token verification failed.', [
                'message' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /** @return list<string> */
    private function allowedAudiences(): array
    {
        $raw = (string) (config('services.apple.client_id') ?? '');

        return array_values(array_filter(array_map('trim', explode(',', $raw))));
    }

    /** @return array{0:string,1:string,2:string} */
    private function split(string $jwt): array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) {
            throw new \InvalidArgumentException('Malformed JWT.');
        }

        return [$parts[0], $parts[1], $parts[2]];
    }

    private function pemForKid(string $kid): ?string
    {
        $jwks = $this->jwks();
        foreach ($jwks['keys'] ?? [] as $key) {
            if (($key['kid'] ?? null) === $kid && isset($key['n'], $key['e'])) {
                return $this->jwkToPem((string) $key['n'], (string) $key['e']);
            }
        }

        // Key rotation: refresh once and retry before giving up.
        Cache::forget(self::JWKS_CACHE_KEY);
        $jwks = $this->jwks();
        foreach ($jwks['keys'] ?? [] as $key) {
            if (($key['kid'] ?? null) === $kid && isset($key['n'], $key['e'])) {
                return $this->jwkToPem((string) $key['n'], (string) $key['e']);
            }
        }

        return null;
    }

    /** @return array<string, mixed> */
    private function jwks(): array
    {
        return Cache::remember(self::JWKS_CACHE_KEY, now()->addHours(12), function () {
            $response = Http::timeout(12)->get(self::JWKS_URL);
            if (! $response->successful()) {
                return ['keys' => []];
            }
            $json = $response->json();

            return is_array($json) ? $json : ['keys' => []];
        });
    }

    /**
     * Builds a PEM public key from a JWK RSA modulus/exponent (SPKI DER).
     */
    private function jwkToPem(string $n, string $e): string
    {
        $modulus = $this->derInteger($this->b64urlDecode($n));
        $exponent = $this->derInteger($this->b64urlDecode($e));
        $rsaPublicKey = $this->derSequence($modulus.$exponent);

        // AlgorithmIdentifier for rsaEncryption (OID 1.2.840.113549.1.1.1) + NULL.
        $algorithm = pack('H*', '300d06092a864886f70d0101010500');
        $bitString = "\x03".$this->derLength(strlen($rsaPublicKey) + 1)."\x00".$rsaPublicKey;
        $spki = $this->derSequence($algorithm.$bitString);

        return "-----BEGIN PUBLIC KEY-----\n"
            .chunk_split(base64_encode($spki), 64, "\n")
            ."-----END PUBLIC KEY-----\n";
    }

    private function derSequence(string $contents): string
    {
        return "\x30".$this->derLength(strlen($contents)).$contents;
    }

    private function derInteger(string $bytes): string
    {
        // Prepend 0x00 when the high bit is set so the integer stays positive.
        if ($bytes !== '' && (ord($bytes[0]) & 0x80)) {
            $bytes = "\x00".$bytes;
        }

        return "\x02".$this->derLength(strlen($bytes)).$bytes;
    }

    private function derLength(int $length): string
    {
        if ($length < 128) {
            return chr($length);
        }
        $bytes = '';
        while ($length > 0) {
            $bytes = chr($length & 0xFF).$bytes;
            $length >>= 8;
        }

        return chr(0x80 | strlen($bytes)).$bytes;
    }

    private function b64urlDecode(string $value): string
    {
        $padded = strtr($value, '-_', '+/');
        $remainder = strlen($padded) % 4;
        if ($remainder > 0) {
            $padded .= str_repeat('=', 4 - $remainder);
        }

        return (string) base64_decode($padded, true);
    }
}
