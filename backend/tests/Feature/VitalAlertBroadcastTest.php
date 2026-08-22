<?php

namespace Tests\Feature;

use App\Events\VitalAlertBroadcast;
use App\Models\User;
use App\Models\VitalCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Event;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §13 realtime row — verifies the VitalAlertBroadcast event is
 * dispatched when a vital alert is created. Broadcaster is `null` in the
 * test env (phpunit.xml), so this asserts the dispatch, not the delivery.
 */
class VitalAlertBroadcastTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        VitalCatalog::create([
            'vital_key' => 'heart_rate',
            'normal_min' => 60,
            'normal_max' => 100,
            'warning_low' => 50,
            'warning_high' => 120,
            'critical_low' => 40,
            'critical_high' => 150,
            'enabled' => true,
        ]);
    }

    public function test_critical_reading_dispatches_broadcast_event(): void
    {
        Event::fake([VitalAlertBroadcast::class]);

        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 180,
        ])->assertCreated();

        Event::assertDispatched(VitalAlertBroadcast::class, function (VitalAlertBroadcast $event) use ($patient) {
            return $event->patient->id === $patient->id
                && $event->reading->risk === 'critical'
                && $event->notification !== null;
        });
    }

    public function test_normal_reading_does_not_dispatch_broadcast(): void
    {
        Event::fake([VitalAlertBroadcast::class]);

        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 72,
        ])->assertCreated();

        Event::assertNotDispatched(VitalAlertBroadcast::class);
    }

    public function test_broadcast_targets_both_user_and_care_team_channels(): void
    {
        $patient = User::factory()->role('patient')->create();
        $reading = $patient->vitalReadings()->create([
            'vital_key' => 'heart_rate',
            'value' => 200,
            'risk' => 'critical',
            'recorded_at' => now(),
        ]);

        $event = new VitalAlertBroadcast($patient, $reading, null);
        $channels = $event->broadcastOn();

        $this->assertCount(2, $channels);
        $this->assertSame('private-user.'.$patient->id, $channels[0]->name);
        $this->assertSame('private-care-team.'.$patient->id, $channels[1]->name);
        $this->assertSame('vital.alert', $event->broadcastAs());
    }
}
