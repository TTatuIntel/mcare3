<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AccountSessionInvalidationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_role_change_revokes_existing_tokens(): void
    {
        $admin = User::factory()->role('admin')->create();
        $doctor = User::factory()->role('doctor')->create();
        $doctor->createToken('existing-device');
        Sanctum::actingAs($admin);

        $this->patchJson("/api/v1/admin/users/{$doctor->id}/role", [
            'role' => 'mcareAssistant',
            'reason' => 'Changed delegated responsibilities.',
        ])->assertOk();

        $this->assertSame(0, $doctor->tokens()->count());
    }

    public function test_status_change_revokes_existing_tokens(): void
    {
        $admin = User::factory()->role('admin')->create();
        $patient = User::factory()->role('patient')->create();
        $patient->createToken('existing-device');
        Sanctum::actingAs($admin);

        $this->patchJson("/api/v1/admin/users/{$patient->id}/status", [
            'status' => 'suspended',
        ])->assertOk();

        $this->assertSame(0, $patient->tokens()->count());
    }

    public function test_inactive_account_is_rejected_even_if_a_token_still_exists(): void
    {
        $patient = User::factory()->role('patient')->create([
            'approval_status' => 'suspended',
        ]);
        $patient->createToken('stale-device');
        Sanctum::actingAs($patient);

        $this->getJson('/api/v1/patient/session')
            ->assertForbidden()
            ->assertJsonPath('data.account_status', 'suspended');

        $this->assertSame(0, $patient->tokens()->count());
    }

    public function test_pending_account_can_check_approval_without_accessing_role_data(): void
    {
        $doctor = User::factory()->role('doctor')->create([
            'approval_status' => 'pending_approval',
        ]);
        $doctor->createToken('pending-approval-screen');
        Sanctum::actingAs($doctor);

        $this->getJson('/api/v1/auth/me')->assertOk();
        $this->getJson('/api/v1/doctor/session')
            ->assertForbidden()
            ->assertJsonPath('data.account_status', 'pendingApproval');

        $this->assertSame(1, $doctor->tokens()->count());
    }
}
