<?php

namespace Tests\Feature;

use App\Mail\EmailVerificationMail;
use App\Models\EmailVerificationCode;
use App\Models\User;
use App\Services\AccountVerificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/**
 * Proving an address, from either end of the message.
 *
 * A code alone assumes the reader can type into the app on the device holding
 * their inbox. Half of them cannot: mail opens on a clinic desktop and the app
 * lives on a handset. So one issue carries two ways to finish — a link and a
 * code — over every channel the account has, and either one completes it.
 *
 * These hold the parts that are easy to get subtly wrong: that the two routes
 * are one act rather than two, that a spent or invented link proves nothing,
 * that a resend really replaces what came before, and that the API never
 * claims delivery it did not get.
 */
class AccountVerificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Mail::fake();
        config()->set('mail.default', 'smtp');
        config()->set('services.sms.default_country_code', '234');
        config()->set('mcare.frontend_url', 'https://app.example.test');
        config()->set('app.url', 'https://api.example.test');
    }

    /** @return array{0: User, 1: string, 2: string} user, code, link token */
    private function register(array $overrides = []): array
    {
        $this->postJson('/api/v1/auth/register', array_merge([
            'first_name' => 'Ada',
            'last_name' => 'Okafor',
            'email' => 'ada@example.com',
            'phone' => '08012345678',
            'password' => 'correct-horse',
        ], $overrides))->assertCreated();

        $user = User::where('email', $overrides['email'] ?? 'ada@example.com')
            ->firstOrFail();

        $code = null;
        $url = null;
        Mail::assertSent(EmailVerificationMail::class, function ($mail) use (&$code, &$url) {
            $code = $mail->code;
            $url = $mail->verifyUrl;

            return true;
        });

        return [$user, (string) $code, (string) basename((string) $url)];
    }

    public function test_one_issue_carries_both_a_code_and_a_link(): void
    {
        [$user, $code, $token] = $this->register();

        $this->assertMatchesRegularExpression('/^\d{6}$/', $code);
        $this->assertNotSame('', $token, 'the mail has to offer a one-tap route too');

        $record = EmailVerificationCode::where('user_id', $user->id)->firstOrFail();
        $this->assertStringStartsWith('$2', $record->code, 'a readable code in the table is a stealable code');
        $this->assertSame(
            hash('sha256', $token),
            $record->link_token,
            'the link token is stored only as a hash',
        );
    }

    public function test_the_link_verifies_the_account_and_lands_on_the_app(): void
    {
        [$user, , $token] = $this->register();

        $this->get("/api/v1/auth/verify-email/{$token}")
            ->assertRedirect(
                'https://app.example.test/verify-email?status=verified&email='
                    .urlencode($user->email),
            );

        $this->assertNotNull($user->fresh()->email_verified_at);
    }

    public function test_a_link_works_once_and_then_proves_nothing(): void
    {
        [, , $token] = $this->register();

        $this->get("/api/v1/auth/verify-email/{$token}")->assertRedirect();

        $this->get("/api/v1/auth/verify-email/{$token}")
            ->assertRedirect('https://app.example.test/verify-email?status=invalid');
    }

    public function test_an_invented_link_is_refused_without_saying_why(): void
    {
        $this->register();

        $this->get('/api/v1/auth/verify-email/'.str_repeat('z', 48))
            ->assertRedirect('https://app.example.test/verify-email?status=invalid');
    }

    public function test_using_the_link_retires_the_code_that_came_with_it(): void
    {
        [$user, $code, $token] = $this->register();

        $this->get("/api/v1/auth/verify-email/{$token}")->assertRedirect();

        // Same act, already finished. The code must not be a second live
        // credential sitting in an inbox after the account is verified.
        $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => $user->email,
            'code' => $code,
            'purpose' => 'email_verify',
        ])->assertStatus(422);
    }

    public function test_a_resend_kills_the_code_it_replaces(): void
    {
        [$user, $firstCode] = $this->register();
        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        $this->withToken($token)
            ->postJson('/api/v1/auth/resend-otp')
            ->assertOk()
            ->assertJsonPath('data.verification_delivery', 'accepted');

        $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => $user->email,
            'code' => $firstCode,
            'purpose' => 'email_verify',
        ])->assertStatus(422);

        $codes = [];
        Mail::assertSent(EmailVerificationMail::class, function ($mail) use (&$codes) {
            $codes[] = $mail->code;

            return true;
        });
        $latest = end($codes);

        $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => $user->email,
            'code' => $latest,
            'purpose' => 'email_verify',
        ])->assertOk()->assertJsonPath('data.user.email_verified', true);
    }

    public function test_the_dispatch_says_where_the_code_went(): void
    {
        // A real gateway, so the SMS leg reports a genuine acceptance rather
        // than the log driver's silent nothing.
        config()->set('services.sms.driver', 'twilio');
        config()->set('services.sms.twilio.sid', 'AC123');
        config()->set('services.sms.twilio.token', 'secret');
        config()->set('services.sms.twilio.from', '+15550000000');
        Http::fake([
            'api.twilio.com/*' => Http::response(['sid' => 'SM1', 'status' => 'queued'], 201),
        ]);

        $body = $this->postJson('/api/v1/auth/register', [
            'first_name' => 'Asha',
            'last_name' => 'Nabirye',
            'email' => 'asha@example.com',
            'phone' => '08099999999',
            'password' => 'correct-horse',
        ])->assertCreated()->json('data.verification');

        $this->assertSame(['email', 'sms'], $body['channels']);
        $this->assertTrue($body['delivered']);
        $this->assertTrue($body['sms_available']);
        $this->assertSame('a••a@example.com', $body['email']);
        $this->assertStringNotContainsString(
            '99999999',
            (string) $body['phone'],
            'a number echoed back in full is a number leaked to whoever is looking',
        );
        $this->assertGreaterThan(0, $body['retry_after']);
    }

    public function test_a_code_can_be_asked_for_by_sms_alone(): void
    {
        config()->set('services.sms.driver', 'twilio');
        config()->set('services.sms.twilio.sid', 'AC123');
        config()->set('services.sms.twilio.token', 'secret');
        config()->set('services.sms.twilio.from', '+15550000000');
        Http::fake([
            'api.twilio.com/*' => Http::response(['sid' => 'SM1', 'status' => 'queued'], 201),
        ]);

        [$user] = $this->register();
        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        $body = $this->withToken($token)
            ->postJson('/api/v1/auth/resend-otp', ['channel' => 'sms'])
            ->assertOk()
            ->json('data.verification');

        $this->assertSame(['sms'], $body['channels']);
    }

    public function test_sms_is_refused_when_there_is_no_number_to_text(): void
    {
        [$user] = $this->register(['email' => 'nophone@example.com', 'phone' => null]);
        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        $this->withToken($token)
            ->postJson('/api/v1/auth/resend-otp', ['channel' => 'sms'])
            ->assertStatus(422);
    }

    public function test_a_wrong_code_burns_after_five_tries(): void
    {
        [$user, $code] = $this->register();

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/verify-otp', [
                'identifier' => $user->email,
                'code' => '000000',
                'purpose' => 'email_verify',
            ])->assertStatus(422);
        }

        // Guessing is over — even the genuine code is dead, so the only way
        // forward is a fresh send. A guesser cannot grind through a million
        // codes, and cannot lock the account out either.
        $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => $user->email,
            'code' => $code,
            'purpose' => 'email_verify',
        ])->assertStatus(422);

        $this->assertNull($user->fresh()->email_verified_at);
    }

    public function test_an_undeliverable_send_is_never_reported_as_sent(): void
    {
        [$user] = $this->register();
        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        // Neither transport can actually deliver: the log mailer swallows mail
        // and no SMS gateway is configured.
        config()->set('mail.default', 'log');
        config()->set('services.sms.driver', 'log');

        $this->withToken($token)
            ->postJson('/api/v1/auth/resend-otp')
            ->assertStatus(502)
            ->assertJsonPath('data.verification_delivery', 'failed')
            ->assertJsonPath('data.verification.channels', []);
    }

    public function test_a_verified_account_is_told_there_is_nothing_to_do(): void
    {
        [$user, $code] = $this->register();
        $this->postJson('/api/v1/auth/verify-otp', [
            'identifier' => $user->email,
            'code' => $code,
            'purpose' => 'email_verify',
        ])->assertOk();

        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => $user->email,
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        $this->withToken($token)
            ->postJson('/api/v1/auth/resend-otp')
            ->assertOk()
            ->assertJsonPath('data.verification_delivery', 'not_required');
    }

    public function test_changing_an_email_verifies_the_new_address_by_email_only(): void
    {
        config()->set('services.sms.driver', 'twilio');
        config()->set('services.sms.twilio.sid', 'AC123');
        config()->set('services.sms.twilio.token', 'secret');
        config()->set('services.sms.twilio.from', '+15550000000');
        Http::fake([
            'api.twilio.com/*' => Http::response(['sid' => 'SM1', 'status' => 'queued'], 201),
        ]);

        $user = User::factory()->create([
            'email' => 'old@example.com',
            'phone' => '08012345678',
            'password' => Hash::make('correct-horse'),
            'email_verified_at' => now(),
        ]);
        $token = $this->postJson('/api/v1/auth/login', [
            'identifier' => 'old@example.com',
            'password' => 'correct-horse',
        ])->assertOk()->json('data.token');

        $body = $this->withToken($token)
            ->postJson('/api/v1/auth/change-email', [
                'current_password' => 'correct-horse',
                'new_email' => 'new@example.com',
            ])->assertOk()->json('data.verification');

        $this->assertSame(
            ['email'],
            $body['channels'],
            'texting the code would let whoever holds the handset confirm an '
                .'address the account holder never chose',
        );
        $this->assertNull($user->fresh()->email_verified_at);
    }

    public function test_the_service_reports_a_cooldown_that_actually_counts_down(): void
    {
        [$user] = $this->register();

        $record = EmailVerificationCode::where('user_id', $user->id)
            ->orderByDesc('created_at')
            ->firstOrFail();
        $service = app(AccountVerificationService::class);

        $this->assertEqualsWithDelta(
            AccountVerificationService::RESEND_COOLDOWN_SECONDS,
            $service->retryAfterSeconds($record),
            2,
            'a freshly sent code has the whole cooldown left to run',
        );

        $record->forceFill([
            'created_at' => now()->subSeconds(
                AccountVerificationService::RESEND_COOLDOWN_SECONDS + 5
            ),
        ])->save();

        $this->assertSame(0, $service->retryAfterSeconds($record->fresh()));
    }
}
