<?php

namespace Tests\Feature;

use App\Support\ProductionReadiness;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class ProductionReadinessTest extends TestCase
{
    use RefreshDatabase;

    public function test_readiness_endpoint_reports_runtime_dependencies_without_secrets(): void
    {
        config(['cache.default' => 'database']);

        $response = $this->getJson('/ready')
            ->assertOk()
            ->assertJsonPath('status', 'ready')
            ->assertJsonPath('checks.database.ok', true)
            ->assertJsonPath('checks.storage.ok', true)
            ->assertJsonPath('checks.cache.detail', 'database');

        $this->assertArrayNotHasKey('environment', $response->json('checks'));
    }

    public function test_readiness_command_is_report_only_unless_strict_is_requested(): void
    {
        $this->artisan('mcare:readiness', ['--json' => true])
            ->expectsOutputToContain('"summary"')
            ->assertSuccessful();

        $this->artisan('mcare:readiness', ['--strict' => true])
            ->assertFailed();
    }

    public function test_demo_seed_override_is_a_failed_production_gate(): void
    {
        config(['mcare.allow_demo_seed' => true]);

        $check = collect(ProductionReadiness::audit())
            ->firstWhere('gate', 'demo-seed');

        $this->assertSame('fail', $check['status']);
    }

    public function test_placeholder_smtp_key_is_reported_without_contacting_the_provider(): void
    {
        config([
            'mail.default' => 'smtp',
            'mail.from.address' => 'onboarding@resend.dev',
            'mail.mailers.smtp.host' => 'smtp.resend.com',
            'mail.mailers.smtp.username' => 'resend',
            'mail.mailers.smtp.password' => 're_REPLACE_WITH_REAL_KEY',
        ]);
        Mail::fake();

        $email = collect(ProductionReadiness::audit())->firstWhere('gate', 'email');
        $this->assertSame('fail', $email['status']);
        $this->assertStringContainsString('still a placeholder', $email['detail']);

        $this->artisan('mcare:mail-test', ['email' => 'owner@example.test'])
            ->expectsOutputToContain('DELIVERY BLOCKED')
            ->expectsOutputToContain('still a placeholder')
            ->assertFailed();
        Mail::assertNothingSent();
    }
}
