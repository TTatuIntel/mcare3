<?php

namespace Tests\Feature;

use App\Models\AppNotification;
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
            'type' => 'service_account',
            'project_id' => 'mcare-test',
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
            Cache::put(
                'fcm_access_token:'.hash(
                    'sha256',
                    'mcare-test|firebase-admin@example.test',
                ),
                'test-access-token',
                60,
            );
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
                'Patient name must not leave the API',
                'Patient detail must not leave the API',
                ['kind' => 'sos', 'patient_name' => 'Private Person'],
            );

            Http::assertSent(function ($request) {
                $message = $request->data()['message'];

                return $message['notification']['title'] === 'Urgent mCare alert'
                    && $message['android']['notification']['channel_id'] === 'sos_emergency'
                    && ! array_key_exists('patient_name', $message['data']);
            });

            $this->assertDatabaseMissing('fcm_tokens', [
                'token' => 'permanently-invalid-device-token',
            ]);
        } finally {
            Cache::forget(
                'fcm_access_token:'.hash(
                    'sha256',
                    'mcare-test|firebase-admin@example.test',
                ),
            );
            if (is_file($path)) {
                unlink($path);
            }
        }
    }

    public function test_persisted_notification_dispatches_one_privacy_safe_push(): void
    {
        $directory = storage_path('framework/testing');
        if (! is_dir($directory)) {
            mkdir($directory, 0775, true);
        }
        $path = $directory.'/fcm-service-account-observer-test.json';
        file_put_contents($path, json_encode([
            'type' => 'service_account',
            'project_id' => 'mcare-test',
            'client_email' => 'firebase-admin@example.test',
            'private_key' => 'test-private-key-not-used',
        ], JSON_THROW_ON_ERROR));

        $cacheKey = 'fcm_access_token:'.hash(
            'sha256',
            'mcare-test|firebase-admin@example.test',
        );
        try {
            config([
                'services.fcm.project_id' => 'mcare-test',
                'services.fcm.service_account_path' => 'storage/framework/testing/fcm-service-account-observer-test.json',
            ]);
            Cache::put($cacheKey, 'test-access-token', 60);
            Http::fake([
                'https://fcm.googleapis.com/*' => Http::response(['name' => 'sent'], 200),
            ]);

            $user = User::factory()->create();
            FcmToken::create([
                'user_id' => $user->id,
                'token' => 'active-device-token',
                'platform' => 'android',
                'last_seen_at' => now(),
            ]);

            $notification = AppNotification::create([
                'user_id' => $user->id,
                'kind' => 'medication',
                'title' => 'Private prescription title',
                'body' => 'Private medication detail',
                'action_route' => '/patient/medications',
                'read' => false,
                'resolved' => false,
            ]);

            Http::assertSent(function ($request) use ($notification) {
                $message = $request->data()['message'];

                return $message['token'] === 'active-device-token'
                    && $message['notification']['title'] === 'New mCare update'
                    && $message['android']['notification']['channel_id'] === 'mcare_updates'
                    && $message['data']['kind'] === 'medication'
                    && $message['data']['notification_id'] === (string) $notification->id;
            });

            // SOS owns a richer dedicated dispatcher; the generic observer
            // must not produce a second push for the same emergency.
            AppNotification::create([
                'user_id' => $user->id,
                'kind' => 'sos',
                'title' => 'SOS',
                'body' => 'Emergency',
                'read' => false,
                'resolved' => false,
            ]);
            Http::assertSentCount(1);
        } finally {
            Cache::forget($cacheKey);
            if (is_file($path)) {
                unlink($path);
            }
        }
    }
}
