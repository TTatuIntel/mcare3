<?php

namespace Tests\Feature;

use App\Mail\PasswordResetMail;
use App\Models\EmailVerificationCode;
use App\Models\FcmToken;
use App\Models\User;
use App\Support\SmsSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/**
 * Account recovery: emailed reset link, SMS OTP, and the token exchange
 * between them. Covers the enumeration guard and both expiry clocks.
 */
class PasswordRecoveryTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Mail::fake();
        config()->set('services.sms.default_country_code', '234');
    }

    private function makeUser(array $overrides = []): User
    {
        return User::factory()->create(array_merge([
            'email' => 'user@example.com',
            'phone' => '08012345678',
            'password' => Hash::make('correct-horse'),
        ], $overrides));
    }

    public function test_email_channel_sends_reset_mail_and_masks_destination(): void
    {
        $user = $this->makeUser();

        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => 'user@example.com',
        ])
            ->assertOk()
            ->assertJsonPath('data.channel', 'email')
            ->assertJsonPath('data.destination', 'u••r@example.com');

        Mail::assertSent(PasswordResetMail::class, fn ($mail) => $mail->hasTo($user->email));
        $this->assertDatabaseHas('password_reset_tokens', ['email' => $user->email]);
    }

    public function test_unknown_identifier_does_not_reveal_account(): void
    {
        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => 'nobody@example.com',
        ])
            ->assertOk()
            ->assertJsonPath('data.channel', 'email');

        Mail::assertNothingSent();
        $this->assertDatabaseCount('password_reset_tokens', 0);
    }

    public function test_sms_channel_stores_hashed_otp_and_texts_the_user(): void
    {
        config()->set('services.sms.driver', 'twilio');
        config()->set('services.sms.default_country_code', '234');
        config()->set('services.sms.twilio', [
            'sid' => 'AC-test', 'token' => 'secret', 'from' => '+15550001111',
        ]);
        Http::fake(['api.twilio.com/*' => Http::response(['sid' => 'SM1'], 201)]);

        $user = $this->makeUser();

        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => '08012345678',
            'channel' => 'sms',
        ])
            ->assertOk()
            ->assertJsonPath('data.channel', 'sms')
            ->assertJsonPath('data.destination', '+234••••••5678');

        $record = EmailVerificationCode::where('user_id', $user->id)
            ->where('purpose', 'password_reset')->firstOrFail();
        $this->assertStringStartsWith('$2', $record->code, 'OTP must be stored hashed.');

        Http::assertSent(fn ($request) => $request['To'] === '+2348012345678'
            && str_contains((string) $request['Body'], 'mCare password reset code'));
        Mail::assertNothingSent();
    }

    public function test_sms_channel_never_exposes_a_phone_from_an_email_identifier(): void
    {
        $this->makeUser();

        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => 'user@example.com',
            'channel' => 'sms',
        ])
            ->assertOk()
            ->assertJsonPath('data.channel', 'sms');

        Mail::assertNothingSent();
        $this->assertDatabaseMissing('email_verification_codes', [
            'purpose' => 'password_reset',
        ]);
    }

    public function test_unknown_identifier_does_not_leak_through_the_channel(): void
    {
        // A known phone-bearing account answers "sms". An unknown identifier
        // must answer "sms" too, or the channel becomes an existence oracle.
        $this->makeUser();

        $known = $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => '08012345678', 'channel' => 'sms',
        ])->assertOk()->json('data.channel');

        $unknown = $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => '09099999999', 'channel' => 'sms',
        ])->assertOk()->json('data.channel');

        $this->assertSame('sms', $known);
        $this->assertSame($known, $unknown);
    }

    public function test_otp_exchanges_for_a_token_that_resets_the_password(): void
    {
        $user = $this->makeUser();
        $code = $this->issueSmsCode($user);

        $grant = $this->postJson('/api/v1/auth/verify-reset-otp', [
            'identifier' => '08012345678',
            'code' => $code,
        ])->assertOk()->json('data');

        $this->assertSame($user->email, $grant['email']);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $grant['email'],
            'token' => $grant['token'],
            'password' => 'brand-new-secret',
        ])->assertOk();

        $this->assertTrue(Hash::check('brand-new-secret', $user->fresh()->password));
        $this->assertDatabaseCount('password_reset_tokens', 0);
    }

    public function test_otp_is_single_use(): void
    {
        $user = $this->makeUser();
        $code = $this->issueSmsCode($user);

        $this->postJson('/api/v1/auth/verify-reset-otp', [
            'identifier' => '08012345678', 'code' => $code,
        ])->assertOk();

        $this->postJson('/api/v1/auth/verify-reset-otp', [
            'identifier' => '08012345678', 'code' => $code,
        ])->assertStatus(422);
    }

    public function test_otp_burns_after_five_wrong_attempts(): void
    {
        $user = $this->makeUser();
        $code = $this->issueSmsCode($user);
        $wrong = $code === '000000' ? '111111' : '000000';

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/verify-reset-otp', [
                'identifier' => '08012345678', 'code' => $wrong,
            ])->assertStatus(422);
        }

        $this->postJson('/api/v1/auth/verify-reset-otp', [
            'identifier' => '08012345678', 'code' => $code,
        ])->assertStatus(422);
    }

    public function test_expired_reset_token_is_rejected(): void
    {
        $user = $this->makeUser();
        DB::table('password_reset_tokens')->insert([
            'email' => $user->email,
            'token' => Hash::make('stale-token'),
            'created_at' => now()->subMinutes(
                (int) config('mcare.auth.reset_token_minutes', 60) + 5,
            ),
        ]);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => 'stale-token',
            'password' => 'brand-new-secret',
        ])->assertStatus(422);

        $this->assertTrue(Hash::check('correct-horse', $user->fresh()->password));
    }

    public function test_reset_revokes_every_existing_session(): void
    {
        $user = $this->makeUser();
        $user->createToken('old device')->plainTextToken;
        FcmToken::create([
            'user_id' => $user->id,
            'token' => 'old-fcm-token',
            'platform' => 'android',
            'last_seen_at' => now(),
        ]);
        DB::table('password_reset_tokens')->insert([
            'email' => $user->email,
            'token' => Hash::make('fresh-token'),
            'created_at' => now(),
        ]);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => 'fresh-token',
            'password' => 'brand-new-secret',
        ])->assertOk();

        $this->assertSame(0, $user->tokens()->count());
        $this->assertSame(0, $user->fcmTokens()->count());
    }

    public function test_remember_me_issues_a_longer_lived_token(): void
    {
        $this->makeUser();

        $short = $this->postJson('/api/v1/auth/login', [
            'identifier' => 'user@example.com',
            'password' => 'correct-horse',
        ])->assertOk();

        $long = $this->postJson('/api/v1/auth/login', [
            'identifier' => 'user@example.com',
            'password' => 'correct-horse',
            'remember' => true,
        ])->assertOk()->assertJsonPath('data.remember', true);

        $this->assertTrue(
            strtotime($long->json('data.expires_at'))
                > strtotime($short->json('data.expires_at')),
            'A remembered session must outlive a plain one.',
        );
    }

    public function test_sms_sender_normalizes_local_numbers_to_e164(): void
    {
        config()->set('services.sms.default_country_code', '234');
        $sms = new SmsSender;

        $this->assertSame('+2348012345678', $sms->normalize('080 1234 5678'));
        $this->assertSame('+2348012345678', $sms->normalize('+234 801 234 5678'));
        $this->assertSame('+2348012345678', $sms->normalize('00234-801-234-5678'));
        $this->assertNull($sms->normalize('abc'));
    }

    public function test_login_and_recovery_match_local_and_international_phone_formats(): void
    {
        $user = $this->makeUser();
        $this->assertSame('+2348012345678', $user->phone_e164);

        $this->postJson('/api/v1/auth/login', [
            'identifier' => '+234 801 234 5678',
            'password' => 'correct-horse',
        ])->assertOk();

        $sms = new CapturingSmsSender;
        $this->app->instance(SmsSender::class, $sms);
        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => '+234 801 234 5678',
            'channel' => 'sms',
        ])->assertOk();

        $this->assertNotNull($sms->lastMessage);
    }

    /**
     * Drives the real forgot-password endpoint with a capturing SmsSender, so
     * the assertions run against the code the app actually issued rather than
     * one the test invented. The stored code is hashed and unrecoverable.
     */
    private function issueSmsCode(User $user): string
    {
        $sms = new CapturingSmsSender;
        $this->app->instance(SmsSender::class, $sms);

        $this->postJson('/api/v1/auth/forgot-password', [
            'identifier' => (string) $user->phone,
            'channel' => 'sms',
        ])->assertOk();

        $this->assertNotNull($sms->lastMessage, 'No SMS was dispatched.');
        preg_match('/\b(\d{6})\b/', (string) $sms->lastMessage, $m);
        $this->assertNotEmpty($m, 'SMS body carried no 6-digit code.');

        return $m[1];
    }
}

/** Records the outbound message instead of calling a gateway. */
class CapturingSmsSender extends SmsSender
{
    public ?string $lastTo = null;

    public ?string $lastMessage = null;

    public function send(string $to, string $message): bool
    {
        $this->lastTo = $to;
        $this->lastMessage = $message;

        return true;
    }
}
