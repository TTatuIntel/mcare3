<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Tests\TestCase;

/**
 * The demo account picker posts an unverified `mock…` id_token, which the API
 * accepts at face value. That must never be a way into a real account:
 * it is opt-in in every environment and never signs in staff even where it is
 * deliberately enabled.
 */
class MockSocialSignInGuardTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_mock_google_cannot_sign_in_an_admin(): void
    {
        config(['mcare.allow_mock_social_login' => true]);
        User::factory()->role('admin')->create(['email' => 'boss@mcare.test']);

        $this->postJson('/api/v1/auth/google', [
            'id_token' => 'mock-anything',
            'email' => 'boss@mcare.test',
        ])->assertStatus(403);
    }

    public function test_mock_apple_cannot_sign_in_a_doctor(): void
    {
        config(['mcare.allow_mock_social_login' => true]);
        User::factory()->role('doctor')->create(['email' => 'doc@mcare.test']);

        $this->postJson('/api/v1/auth/apple', [
            'id_token' => 'mock-anything',
            'email' => 'doc@mcare.test',
        ])->assertStatus(403);
    }

    public function test_mock_sign_in_is_refused_entirely_when_disabled(): void
    {
        config(['mcare.allow_mock_social_login' => false]);
        User::factory()->role('patient')->create(['email' => 'pat@mcare.test']);

        $this->postJson('/api/v1/auth/google', [
            'id_token' => 'mock-anything',
            'email' => 'pat@mcare.test',
        ])->assertStatus(401);
    }

    public function test_patient_demo_sign_in_still_works_locally(): void
    {
        config(['mcare.allow_mock_social_login' => true]);
        User::factory()->role('patient')->create(['email' => 'pat@mcare.test']);

        $this->postJson('/api/v1/auth/google', [
            'id_token' => 'mock-anything',
            'email' => 'pat@mcare.test',
        ])->assertStatus(200)->assertJsonPath('success', true);
    }

    public function test_default_disables_mock_sign_in_in_every_environment(): void
    {
        $originalEnv = $_ENV['APP_ENV'] ?? null;
        $originalFlag = $_ENV['ALLOW_MOCK_SOCIAL_LOGIN'] ?? null;
        $_ENV['APP_ENV'] = 'local';
        unset($_ENV['ALLOW_MOCK_SOCIAL_LOGIN']);

        try {
            $fresh = require config_path('mcare.php');
            $this->assertFalse(
                $fresh['allow_mock_social_login'],
                'Mock social sign-in must be explicitly enabled in every environment.',
            );
        } finally {
            if ($originalEnv === null) {
                unset($_ENV['APP_ENV']);
            } else {
                $_ENV['APP_ENV'] = $originalEnv;
            }
            if ($originalFlag !== null) {
                $_ENV['ALLOW_MOCK_SOCIAL_LOGIN'] = $originalFlag;
            }
        }
    }
}
