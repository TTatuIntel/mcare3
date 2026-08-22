<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\SosEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §13 — SOS flow coverage.
 * Trigger → notification + audit written → resolve → audit updated.
 */
class SosFlowTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_trigger_creates_event_notification_and_audit(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/sos', [
            'kind' => 'medical',
            'location_label' => 'Home',
            'latitude' => 1.2,
            'longitude' => 32.6,
            'note' => 'Chest pain',
        ])->assertCreated();

        $eventId = $response->json('data.event.id');

        $this->assertDatabaseHas('sos_events', [
            'id' => $eventId,
            'user_id' => $patient->id,
            'status' => 'active',
            'kind' => 'medical',
        ]);
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'sos',
        ]);
        $this->assertDatabaseHas('audit_entries', [
            'actor_user_id' => $patient->id,
            'action' => 'Triggered SOS',
            'category' => 'sos',
        ]);
    }

    public function test_second_trigger_while_active_returns_existing_event(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $first = $this->postJson('/api/v1/patient/sos', [
            'kind' => 'panic',
        ])->assertCreated();

        $second = $this->postJson('/api/v1/patient/sos', [
            'kind' => 'panic',
        ])->assertOk(); // 200 not 201 — existing event returned

        $this->assertSame(
            $first->json('data.event.id'),
            $second->json('data.event.id'),
        );
        $this->assertSame(1, SosEvent::where('user_id', $patient->id)->count());
    }

    public function test_resolve_updates_event_and_resolves_related_notifications(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $event = SosEvent::create([
            'user_id' => $patient->id,
            'kind' => 'fall',
            'status' => 'active',
            'triggered_at' => now(),
        ]);
        $openNotif = AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'sos',
            'title' => 'x',
            'body' => 'y',
            'action_arguments' => ['event_id' => (string) $event->id],
            'read' => false,
            'resolved' => false,
        ]);

        $this->patchJson("/api/v1/patient/sos/{$event->id}", [
            'status' => 'resolved',
            'responded_by' => 'Self',
        ])->assertOk();

        $this->assertSame('resolved', $event->fresh()->status);
        $this->assertNotNull($event->fresh()->responded_at);
        $this->assertTrue($openNotif->fresh()->resolved);
    }

    public function test_cannot_resolve_another_users_event(): void
    {
        $owner = User::factory()->role('patient')->create();
        $intruder = User::factory()->role('patient')->create();

        $event = SosEvent::create([
            'user_id' => $owner->id,
            'kind' => 'panic',
            'status' => 'active',
            'triggered_at' => now(),
        ]);

        Sanctum::actingAs($intruder);

        $this->patchJson("/api/v1/patient/sos/{$event->id}", [
            'status' => 'resolved',
        ])->assertStatus(403);
    }
}
