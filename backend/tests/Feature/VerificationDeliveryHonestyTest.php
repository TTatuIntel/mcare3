<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\SmsSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A code the server could not send must never be reported as sent.
 *
 * The audit recorded this as an open defect — "the SMS fallback reports success
 * and sends nothing" — on the strength of a log line showing the log driver
 * writing a code moments after email delivery failed. These pin what the stack
 * actually does, because a wrong entry in a defect list is expensive: someone
 * eventually "fixes" a path that was already correct and breaks it.
 *
 * The chain that has to hold: the log driver is not a gateway, so the sender
 * returns false; a dispatch with no delivered channel is not delivered; and an
 * undelivered dispatch answers 502 rather than 200, so a client cannot render
 * it as success.
 */
class VerificationDeliveryHonestyTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        config(['services.sms.driver' => 'log']);
    }

    public function test_the_log_driver_is_not_reported_as_a_gateway(): void
    {
        $sent = app(SmsSender::class)->send('+256700000000', 'test');

        $this->assertFalse(
            $sent,
            'The log driver wrote a line and called it delivery.',
        );
    }

    public function test_an_undelivered_resend_answers_502_not_200(): void
    {
        $user = User::factory()->role('patient')->create([
            'email' => 'grace@example.com',
            'phone' => '+256700000000',
            'email_verified_at' => null,
        ]);

        // Mail that throws is the live failure: an exhausted quota or a
        // rejected credential, which is exactly what was happening.
        Mail::shouldReceive('to')->andThrow(new \RuntimeException('535 auth failed'));

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/v1/auth/resend-otp', [
            'identifier' => 'grace@example.com',
            'channel' => 'all',
        ]);

        $response->assertStatus(502);
        $response->assertJsonPath('data.verification_delivery', 'failed');
        $response->assertJsonPath('data.verification.delivered', false);
    }

    public function test_an_sms_only_resend_with_no_gateway_also_fails(): void
    {
        $user = User::factory()->role('patient')->create([
            'email' => 'grace@example.com',
            'phone' => '+256700000000',
            'email_verified_at' => null,
        ]);

        Sanctum::actingAs($user);

        // Nothing is wrong with the address here — there is simply no SMS
        // gateway, and the log driver must not paper over that.
        $response = $this->postJson('/api/v1/auth/resend-otp', [
            'identifier' => 'grace@example.com',
            'channel' => 'sms',
        ]);

        $response->assertStatus(502);
        $response->assertJsonPath('data.verification.delivered', false);
        $this->assertStringContainsString(
            'SMS could not be delivered',
            $response->json('message'),
        );
    }

    public function test_a_delivered_resend_still_answers_200(): void
    {
        $user = User::factory()->role('patient')->create([
            'email' => 'grace@example.com',
            'email_verified_at' => null,
        ]);

        // A transport that accepts the message is the whole difference.
        // The mailer name has to read as a real one: MailDispatcher refuses to
        // call `log` or `array` a delivery, which is the behaviour the first
        // three cases rely on.
        config(['mail.default' => 'smtp']);
        Mail::fake();

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/v1/auth/resend-otp', [
            'identifier' => 'grace@example.com',
            'channel' => 'email',
        ]);

        $response->assertOk();
        $response->assertJsonPath('data.verification_delivery', 'accepted');
        $response->assertJsonPath('data.verification.delivered', true);
    }
}
