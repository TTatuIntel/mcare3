<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StaffNotificationStateTest extends TestCase
{
    use RefreshDatabase;

    public function test_staff_can_persist_and_fetch_notification_read_state(): void
    {
        $user = User::factory()->role('doctor')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states', [
            'key' => 'staff_alert_42',
            'read' => true,
        ])->assertOk();

        $this->assertDatabaseHas('staff_notification_states', [
            'user_id' => $user->id,
            'notification_key' => 'staff_alert_42',
        ]);

        $this->getJson('/api/v1/me/notification-states')
            ->assertOk()
            ->assertJsonFragment(['key' => 'staff_alert_42', 'read' => true, 'resolved' => false]);
    }

    public function test_resolving_implies_read(): void
    {
        $user = User::factory()->role('admin')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states', [
            'key' => 'staff_sos_7',
            'resolved' => true,
        ])->assertOk();

        $this->getJson('/api/v1/me/notification-states')
            ->assertOk()
            ->assertJsonFragment(['key' => 'staff_sos_7', 'read' => true, 'resolved' => true]);
    }

    public function test_read_all_marks_supplied_keys(): void
    {
        $user = User::factory()->role('doctor')->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/me/notification-states/read-all', [
            'keys' => ['staff_alert_1', 'staff_req_2'],
        ])->assertOk();

        $this->assertDatabaseCount('staff_notification_states', 2);
    }

    public function test_state_is_scoped_to_the_authenticated_user(): void
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
            ->assertJsonMissing(['key' => 'staff_alert_99']);
    }

    public function test_requires_authentication(): void
    {
        $this->getJson('/api/v1/me/notification-states')->assertUnauthorized();
    }
}
