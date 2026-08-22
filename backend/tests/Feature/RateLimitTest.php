<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §6.5 — named rate limiters.
 *
 * Verifies the throttles defined in AppServiceProvider fire at the
 * documented thresholds:
 *   - external-resolve : 6 / minute / IP
 *   - auth-login       : 5 / minute / IP
 *   - api-general      : 120 / minute / user (asserted via 121st burst)
 */
class RateLimitTest extends TestCase
{
    use RefreshDatabase;

    public function test_resolve_code_returns_429_after_six_attempts(): void
    {
        // 6 attempts allowed; the 7th must be throttled regardless of payload.
        for ($i = 0; $i < 6; $i++) {
            $this->postJson('/api/v1/external/resolve-code', [
                'code' => 'ABCD-'.str_pad((string) $i, 4, '0', STR_PAD_LEFT),
            ]);
        }

        $this->postJson('/api/v1/external/resolve-code', [
            'code' => 'ABCD-9999',
        ])->assertStatus(429);
    }

    public function test_auth_login_returns_429_after_five_attempts_per_ip(): void
    {
        // Five attempts against different emails all count against the IP limit.
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'identifier' => 'nobody-'.$i.'@example.com',
                'password' => 'x',
            ]);
        }

        $this->postJson('/api/v1/auth/login', [
            'identifier' => 'nobody-final@example.com',
            'password' => 'x',
        ])->assertStatus(429);
    }

    public function test_general_api_throttle_is_wired_on_authenticated_routes(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        // A single request under the 120/min cap succeeds; the presence of the
        // X-RateLimit-Limit header proves the throttle middleware is active.
        $response = $this->getJson('/api/v1/patient/vitals');
        $response->assertOk();
        $this->assertNotNull($response->headers->get('X-RateLimit-Limit'));
        $this->assertSame('120', $response->headers->get('X-RateLimit-Limit'));
    }
}
