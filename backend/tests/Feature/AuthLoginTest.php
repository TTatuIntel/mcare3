<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * README §13 — auth flow coverage.
 * Complements the throttle test in RateLimitTest; this test drives
 * the account-level lockout defined on the User model.
 */
class AuthLoginTest extends TestCase
{
    use RefreshDatabase;

    public function test_valid_credentials_return_token(): void
    {
        User::factory()->create([
            'email' => 'user@example.com',
            'password' => Hash::make('correct-horse'),
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'identifier' => 'user@example.com',
            'password' => 'correct-horse',
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonStructure(['data' => ['token', 'user']]);
    }

    public function test_wrong_password_returns_validation_error(): void
    {
        User::factory()->create([
            'email' => 'user@example.com',
            'password' => Hash::make('correct-horse'),
        ]);

        $this->postJson('/api/v1/auth/login', [
            'identifier' => 'user@example.com',
            'password' => 'wrong',
        ])->assertStatus(422);
    }

    public function test_account_locks_after_five_failed_attempts(): void
    {
        // Bypass the request-throttle so this test isolates the account-level
        // lockout defined on the User model. RateLimitTest covers the throttle
        // behaviour separately.
        $this->withoutMiddleware(ThrottleRequests::class);

        $user = User::factory()->create([
            'email' => 'lockme@example.com',
            'password' => Hash::make('correct-horse'),
        ]);

        for ($i = 0; $i < User::MAX_FAILED_LOGINS; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'identifier' => 'lockme@example.com',
                'password' => 'wrong-'.$i,
            ]);
        }

        $this->assertTrue($user->fresh()->isLocked());

        // Even the correct password is rejected while locked.
        $this->postJson('/api/v1/auth/login', [
            'identifier' => 'lockme@example.com',
            'password' => 'correct-horse',
        ])->assertStatus(423);
    }
}
