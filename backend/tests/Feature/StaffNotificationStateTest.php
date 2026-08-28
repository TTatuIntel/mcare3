<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StaffNotificationStateTest extends TestCase
{
    use RefreshDatabase;

    public function test_computed_notification_state_is_accepted_without_being_persisted(): void
    {
        $user = User::factory()->role('doctor')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states', [
            'key' => 'staff_alert_42',
            'read' => true,
        ])->assertOk()
            ->assertJsonPath('data.state.key', 'staff_alert_42')
            ->assertJsonPath('data.state.read', true)
            ->assertJsonPath('data.state.resolved', false);

        $this->assertDatabaseCount('staff_notification_states', 0);

        $this->getJson('/api/v1/me/notification-states')
            ->assertOk()
            ->assertExactJson([
                'success' => true,
                'message' => 'Operation successful',
                'data' => ['states' => []],
            ]);
    }

    public function test_resolving_implies_read(): void
    {
        $user = User::factory()->role('admin')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states', [
            'key' => 'staff_sos_7',
            'resolved' => true,
        ])->assertOk()
            ->assertJsonPath('data.state.key', 'staff_sos_7')
            ->assertJsonPath('data.state.read', true)
            ->assertJsonPath('data.state.resolved', true);

        $this->assertDatabaseCount('staff_notification_states', 0);
    }

    public function test_read_all_marks_supplied_keys(): void
    {
        $user = User::factory()->role('doctor')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states/read-all', [
            'keys' => ['staff_alert_1', 'staff_req_2'],
        ])->assertOk();

        $this->assertDatabaseCount('staff_notification_states', 0);
    }

    public function test_ephemeral_state_is_not_exposed_to_another_user(): void
    {
        $owner = User::factory()->role('doctor')->create();
        $other = User::factory()->role('doctor')->create();

        Sanctum::actingAs($owner);
        $this->postJson('/api/v1/me/notification-states', [
            'key' => 'staff_alert_99',
            'read' => true,
        ])->assertOk();

        Sanctum::actingAs($other);
        $this->getJson('/api/v1/me/notification-states')
            ->assertOk()
            ->assertJsonPath('data.states', []);
    }

    public function test_requires_authentication(): void
    {
        $this->getJson('/api/v1/me/notification-states')->assertUnauthorized();
    }
}
