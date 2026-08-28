<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A patient account is never re-roled.
 *
 * Promoting a patient into a clinical or staff role would bypass invite-based
 * staff onboarding and its licence/permission checks; demoting staff to
 * patient would leave an account with no clinical record. The admin UI hides
 * the action, and this pins the server-side refusal that makes hiding it safe.
 */
class PatientRoleImmutableTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_admin_cannot_promote_a_patient(): void
    {
        $admin = User::factory()->role('admin')->create();
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/v1/admin/users/{$patient->id}/role", [
            'role' => 'doctor',
            'reason' => 'Attempted promotion via the directory.',
        ]);

        $response->assertStatus(422);
        $this->assertSame('patient', $patient->fresh()->role);
    }

    public function test_admin_cannot_demote_staff_to_patient(): void
    {
        $admin = User::factory()->role('admin')->create();
        $doctor = User::factory()->role('doctor')->create();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/v1/admin/users/{$doctor->id}/role", [
            'role' => 'patient',
            'reason' => 'Attempted demotion via the directory.',
        ]);

        $response->assertStatus(422);
        $this->assertSame('doctor', $doctor->fresh()->role);
    }

    public function test_staff_to_staff_role_change_still_works(): void
    {
        $admin = User::factory()->role('admin')->create();
        $doctor = User::factory()->role('doctor')->create();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/v1/admin/users/{$doctor->id}/role", [
            'role' => 'admin',
            'reason' => 'Promoted to administrator.',
        ]);

        $response->assertStatus(200);
        $this->assertSame('admin', $doctor->fresh()->role);
    }
}
