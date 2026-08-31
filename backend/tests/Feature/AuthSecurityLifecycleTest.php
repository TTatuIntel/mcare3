<?php

namespace Tests\Feature;

use App\Mail\EmailVerificationMail;
use App\Models\EmailVerificationCode;
use App\Models\User;
use App\Support\AppleIdTokenVerifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

class AuthSecurityLifecycleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Mail::fake();
        config()->set('mail.default', 'smtp');
        config()->set('services.sms.default_country_code', '234');
    }

    public function test_registration_is_unverified_and_otp_preserves_remembered_session(): void
    {
        $plainCode = null;
        Mail::assertNothingSent();

        $registered = $this->postJson('/api/v1/auth/register', [
            'first_name' => 'Ada',
            'last_name' => 'Okafor',
            'email' => 'ada@example.com',
            'phone' => '08012345678',
            'password' => 'correct-horse',
            'remember' => true,
            'device_name' => 'Ada Android',
        ])->assertCreated()
            ->assertJsonPath('data.remember', true)
            ->assertJsonPath('data.verification_delivery', 'accepted')
            ->assertJsonPath('data.user.email_verified', false);

        $user = User::where('email', 'ada@example.com')->firstOrFail();
        $this->assertNull($user->email_verified_at);

        $record = EmailVerificationCode::where('user_id', $user->id)
            ->where('purpose', 'email_verify')
            ->firstOrFail();
        $this->assertStringStartsWith('$2', $record->code);

        Mail::assertSent(EmailVerificationMail::class, function ($mail) use (&$plainCode): bool {
            $plainCode = $mail->code;

            return $mail->hasTo('ada@example.com');
        });
        $this->assertNotNull($plainCode);
        $this->assertTrue(Hash::check($plainCode, $record->code));

        $this->withToken($registered->json('data.token'))
            ->getJson('/api/v1/patient/session')
            ->assertForbidden();

        $verified = $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => 'ada@example.com',
            'code' => $plainCode,
            'purpose' => 'email_verify',
            'remember' => true,
            'device_name' => 'Ada Android',
        ])->assertOk()
            ->assertJsonPath('data.remember', true)
            ->assertJsonPath('data.user.email_verified', true);

        $remainingDays = now()->diffInDays($verified->json('data.expires_at'));
        $this->assertGreaterThanOrEqual(29, $remainingDays);
        $this->assertNotNull($user->fresh()->email_verified_at);
    }

    public function test_verification_resend_is_authenticated_and_reports_transport_failure(): void
    {
        $registered = $this->postJson('/api/v1/auth/register', [
            'first_name' => 'Asha',
            'last_name' => 'Nabirye',
            'email' => 'asha@example.com',
            'phone' => '0700000000',
            'password' => 'correct-horse',
        ])->assertCreated();

        $this->postJson('/api/v1/auth/resend-otp', [
            'identifier' => 'asha@example.com',
        ])->assertUnauthorized();

        $this->withToken($registered->json('data.token'))
            ->postJson('/api/v1/auth/resend-otp', [
                'identifier' => 'asha@example.com',
            ])
            ->assertOk()
            ->assertJsonPath('data.verification_delivery', 'accepted');

        config()->set('mail.default', 'log');

        $this->withToken($registered->json('data.token'))
            ->postJson('/api/v1/auth/resend-otp', [
                'identifier' => 'asha@example.com',
            ])
            ->assertStatus(502)
            ->assertJsonPath('data.verification_delivery', 'failed');
    }

    public function test_device_sessions_are_scoped_and_individually_revocable(): void
    {
        $user = User::factory()->create([
            'email' => 'session@example.com',
            'password' => Hash::make('correct-horse'),
        ]);

        $firstToken = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
            'device_name' => 'Clinic laptop',
        ])->assertOk()->json('data.token');

        $secondToken = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
            'device_name' => 'Personal phone',
            'remember' => true,
        ])->assertOk()->json('data.token');

        $sessions = $this->withToken($secondToken)
            ->getJson('/api/v1/auth/sessions')
            ->assertOk()
            ->json('data.sessions');

        $this->assertCount(2, $sessions);
        $this->assertContains('Clinic laptop', array_column($sessions, 'name'));
        $this->assertContains('Personal phone', array_column($sessions, 'name'));
        $this->assertCount(1, array_filter($sessions, fn ($session) => $session['current']));

        $old = collect($sessions)->firstWhere('name', 'Clinic laptop');
        $this->withToken($secondToken)
            ->deleteJson('/api/v1/auth/sessions/'.$old['id'])
            ->assertOk();

        // The feature-test guard caches its resolved bearer identity across
        // requests, so verify revocation against Sanctum's token resolver.
        $this->assertNull(PersonalAccessToken::findToken($firstToken));
        $this->assertNotNull(PersonalAccessToken::findToken($secondToken));
    }

    public function test_apple_sign_in_challenge_is_bound_and_single_use(): void
    {
        $challenge = $this->postJson('/api/v1/auth/apple/challenge')
            ->assertOk()
            ->assertJsonStructure(['data' => ['challenge_id', 'nonce', 'expires_in_seconds']])
            ->json('data');

        $this->app->instance(
            AppleIdTokenVerifier::class,
            new BoundAppleVerifier($challenge['nonce']),
        );

        $body = [
            'id_token' => 'signed-test-token',
            'challenge_id' => $challenge['challenge_id'],
            'create_account' => true,
            'first_name' => 'Amina',
            'last_name' => 'Nabirye',
            'remember' => true,
        ];

        $this->postJson('/api/v1/auth/apple', $body)
            ->assertOk()
            ->assertJsonPath('data.user.email', 'apple-user@example.com')
            ->assertJsonPath('data.remember', true);

        $this->postJson('/api/v1/auth/apple', $body)
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Apple sign-in challenge expired. Please try again.');
    }
}

class BoundAppleVerifier extends AppleIdTokenVerifier
{
    public function __construct(private readonly string $nonce) {}

    public function verify(string $identityToken, ?string $expectedNonceHash = null): ?array
    {
        if ($identityToken !== 'signed-test-token'
            || $expectedNonceHash !== hash('sha256', $this->nonce)) {
            return null;
        }

        return [
            'sub' => 'apple-test-subject',
            'email' => 'apple-user@example.com',
            'nonce' => $this->nonce,
        ];
    }
}
