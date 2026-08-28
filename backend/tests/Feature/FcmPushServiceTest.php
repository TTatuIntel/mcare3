<?php

namespace Tests\Feature;

use App\Models\FcmToken;
use App\Models\User;
use App\Services\FcmPushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FcmPushServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_http_v1_removes_a_permanently_unregistered_device_token(): void
    {
        $directory = storage_path('framework/testing');
        if (! is_dir($directory)) {
            mkdir($directory, 0775, true);
        }
        $path = $directory.'/fcm-service-account-test.json';
        file_put_contents($path, json_encode([
            'client_email' => 'firebase-admin@example.test',
            // The cached access token below means signing is intentionally not
            // exercised; this fixture only validates dispatch/token hygiene.
            'private_key' => 'test-private-key-not-used',
        ], JSON_THROW_ON_ERROR));

        try {
            config([
                'services.fcm.server_key' => null,
                'services.fcm.project_id' => 'mcare-test',
                // Exercise relative-path resolution from the backend root.
                'services.fcm.service_account_path' => 'storage/framework/testing/fcm-service-account-test.json',
            ]);
            Cache::put('fcm_access_token', 'test-access-token', 60);
            Http::fake([
                'https://fcm.googleapis.com/*' => Http::response([
                    'error' => [
                        'status' => 'NOT_FOUND',
                        'details' => [['errorCode' => 'UNREGISTERED']],
                    ],
                ], 404),
            ]);

            $user = User::factory()->create();
            FcmToken::create([
                'user_id' => $user->id,
                'token' => 'permanently-invalid-device-token',
                'platform' => 'android',
            ]);

            FcmPushService::sendToTokens(
                ['permanently-invalid-device-token'],
                'Test',
                'Test body',
            );

            $this->assertDatabaseMissing('fcm_tokens', [
                'token' => 'permanently-invalid-device-token',
            ]);
        } finally {
            Cache::forget('fcm_access_token');
            if (is_file($path)) {
                unlink($path);
            }
        }
    }
}
