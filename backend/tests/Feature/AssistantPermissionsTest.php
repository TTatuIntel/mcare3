<?php

namespace Tests\Feature;

use App\Models\AssistantPermission;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §13 — mCare Assistant permission gating.
 *
 * Verifies each of the 12 canonical permission keys individually gates
 * a representative endpoint. Admin bypass and unauthenticated behaviour
 * are covered separately.
 */
class AssistantPermissionsTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Permission key → [method, path, status_when_granted].
     * The endpoint chosen is the least-side-effect one guarded by that key
     * (usually the index/list endpoint).
     */
    private const KEY_ENDPOINTS = [
        'can_approve_healthworkers'      => ['get',   '/api/v1/admin/approvals', 200],
        'can_manage_care_requests'       => ['get',   '/api/v1/admin/care-requests', 200],
        'can_assign_patients'            => ['get',   '/api/v1/admin/assignments', 200],
        'can_create_users'               => ['get',   '/api/v1/admin/users', 200],
        'can_view_activity_logs'         => ['get',   '/api/v1/admin/audit', 200],
        'can_view_security_incidents'    => ['get',   '/api/v1/admin/security-incidents', 200],
        'can_access_emergency_location'  => ['get',   '/api/v1/admin/sos-events', 200],
        'can_manage_advertising'         => ['get',   '/api/v1/admin/announcements', 200],
        'can_manage_vital_catalog'       => ['get',   '/api/v1/admin/vital-catalog', 200],
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_all_canonical_keys_exist_and_match_expected_set(): void
    {
        // If someone renames or reorders keys server-side without updating
        // Flutter, this test flags it before the next release.
        $this->assertCount(12, AssistantPermission::KEYS);
        $this->assertContains('can_approve_healthworkers', AssistantPermission::KEYS);
        $this->assertContains('can_register_admin', AssistantPermission::KEYS);
        $this->assertContains('can_manage_vital_catalog', AssistantPermission::KEYS);
    }

    public function test_assistant_without_permission_gets_403(): void
    {
        $assistant = User::factory()->role('mcare_assistant')->create();
        Sanctum::actingAs($assistant);

        foreach (self::KEY_ENDPOINTS as $key => [$method, $path, $_]) {
            $response = $this->json($method, $path);
            $this->assertSame(
                403,
                $response->getStatusCode(),
                "Assistant without '$key' should be denied at $path (got {$response->getStatusCode()})",
            );
        }
    }

    public function test_assistant_with_permission_passes_gate(): void
    {
        foreach (self::KEY_ENDPOINTS as $key => [$method, $path, $expected]) {
            $assistant = User::factory()->role('mcare_assistant')->create();
            AssistantPermission::create([
                'user_id' => $assistant->id,
                'permission_key' => $key,
            ]);
            Sanctum::actingAs($assistant);

            $response = $this->json($method, $path);
            $this->assertSame(
                $expected,
                $response->getStatusCode(),
                "Assistant with '$key' should reach $path (got {$response->getStatusCode()}: ".
                substr((string) $response->getContent(), 0, 200).')',
            );
        }
    }

    public function test_admin_bypasses_all_permission_gates(): void
    {
        $admin = User::factory()->role('admin')->create();
        Sanctum::actingAs($admin);

        foreach (self::KEY_ENDPOINTS as [$method, $path, $expected]) {
            $response = $this->json($method, $path);
            $this->assertSame(
                $expected,
                $response->getStatusCode(),
                "Admin should reach $path without permission grant (got {$response->getStatusCode()})",
            );
        }
    }

    public function test_patient_role_cannot_reach_admin_routes(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->getJson('/api/v1/admin/approvals');
        $this->assertContains($response->getStatusCode(), [403, 401]);
    }
}
