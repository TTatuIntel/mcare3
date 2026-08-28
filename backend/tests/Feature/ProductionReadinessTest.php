<?php

namespace Tests\Feature;

use App\Support\ProductionReadiness;
use Illuminate\Foundation\Testing\RefreshDatabase;
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
}
