<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\RealtimeEvent;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Services\RealtimeSignalService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §7.1 — a change has to reach a signed-in client without being asked for.
 *
 * The socket does that in milliseconds, but only where a Reverb server and a
 * queue worker are both running and reachable. Everything here covers the
 * path that has to work when they are not: every signal is buffered, and any
 * client can ask what changed since it last looked, cheaply enough to keep
 * asking every few seconds.
 */
class InstantDeliveryTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        // The buffer exists precisely so this does not matter.
        config(['broadcasting.default' => 'null']);

        VitalCatalog::create([
            'vital_key' => 'blood_oxygen',
            'normal_min' => 95,
            'normal_max' => 100,
            'warning_low' => 92,
            'warning_high' => 100,
            'critical_low' => 88,
            'critical_high' => 100,
            'enabled' => true,
        ]);
    }

    public function test_signals_are_buffered_even_with_no_broadcaster(): void
    {
        $this->assertFalse(RealtimeSignalService::enabled());

        RealtimeSignalService::signal(['user.7'], ['alerts'], 'created', 'AppNotification', 3);

        $this->assertDatabaseHas('realtime_events', [
            'channel' => 'user.7',
            'domains' => 'alerts',
            'resource_type' => 'AppNotification',
        ]);
    }

    public function test_a_muted_snapshot_writes_nothing(): void
    {
        RealtimeSignalService::withoutSignals(function () {
            RealtimeSignalService::signal(['user.7'], ['alerts'], 'created', 'AppNotification', 3);
        });

        $this->assertSame(0, RealtimeEvent::where('channel', 'user.7')->count());
    }

    public function test_a_client_with_no_cursor_gets_a_baseline_not_a_replay(): void
    {
        $patient = User::factory()->role('patient')->create();
        RealtimeSignalService::signal(['user.'.$patient->id], ['vitals'], 'created', 'VitalReading', 1);

        Sanctum::actingAs($patient);
        $this->getJson('/api/v1/me/pulse')
            ->assertOk()
            ->assertJsonPath('data.domains', [])
            ->assertJsonPath('data.stale', false)
            ->assertJsonPath('data.cursor', RealtimeEvent::max('id'));
    }

    public function test_a_patients_critical_reading_shows_up_on_their_next_pulse(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $before = (int) (RealtimeEvent::max('id') ?? 0);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'blood_oxygen',
            'value' => 66,
        ])->assertCreated();

        $body = $this->getJson("/api/v1/me/pulse?since={$before}")
            ->assertOk()
            ->assertJsonPath('data.stale', false)
            ->json('data');

        $this->assertContains('alerts', $body['domains']);
        $this->assertContains('notifications', $body['domains']);
        $this->assertContains('vitals', $body['domains']);
        $this->assertGreaterThan($before, $body['cursor']);
    }

    public function test_the_assigned_doctor_sees_it_on_their_own_pulse(): void
    {
        $patient = User::factory()->role('patient')->create();
        $doctor = User::factory()->role('doctor')->create();
        CareAssignment::create([
            'patient_user_id' => $patient->id,
            'provider_id' => CareProvider::resolveForUser($doctor->id)->id,
            'role' => 'doctor',
            'assigned_at' => now(),
        ]);

        $before = (int) (RealtimeEvent::max('id') ?? 0);

        Sanctum::actingAs($patient);
        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'blood_oxygen',
            'value' => 66,
        ])->assertCreated();

        Sanctum::actingAs($doctor);
        $domains = $this->getJson("/api/v1/me/pulse?since={$before}")
            ->assertOk()
            ->json('data.domains');

        $this->assertContains('alerts', $domains);
    }

    public function test_one_patients_change_is_invisible_to_an_unrelated_patient(): void
    {
        $patient = User::factory()->role('patient')->create();
        $stranger = User::factory()->role('patient')->create();

        $before = (int) (RealtimeEvent::max('id') ?? 0);

        Sanctum::actingAs($patient);
        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'blood_oxygen',
            'value' => 66,
        ])->assertCreated();

        Sanctum::actingAs($stranger);
        $this->getJson("/api/v1/me/pulse?since={$before}")
            ->assertOk()
            ->assertJsonPath('data.domains', []);
    }

    public function test_a_cursor_older_than_the_buffer_is_reported_stale(): void
    {
        $patient = User::factory()->role('patient')->create();
        RealtimeSignalService::signal(['user.'.$patient->id], ['vitals'], 'created', 'VitalReading', 1);
        $missed = (int) RealtimeEvent::max('id');
        RealtimeSignalService::signal(['user.'.$patient->id], ['alerts'], 'created', 'AppNotification', 2);

        // Retention has since swept away everything this client had not yet
        // read, so a clean "nothing changed" would be a lie about the gap.
        RealtimeEvent::where('id', '<=', $missed)->delete();

        Sanctum::actingAs($patient);
        $this->getJson('/api/v1/me/pulse?since='.($missed - 1))
            ->assertOk()
            ->assertJsonPath('data.stale', true);
    }

    public function test_the_pulse_needs_a_session(): void
    {
        $this->getJson('/api/v1/me/pulse')->assertUnauthorized();
    }

    public function test_the_socket_endpoint_is_published_without_its_secret(): void
    {
        config([
            'broadcasting.default' => 'reverb',
            'broadcasting.connections.reverb.app_id' => 'test-app',
            'broadcasting.connections.reverb.key' => 'test-key',
            'broadcasting.connections.reverb.secret' => 'test-secret',
            'broadcasting.connections.reverb.options.host' => 'localhost',
            'broadcasting.connections.reverb.options.port' => 8080,
            'broadcasting.connections.reverb.options.scheme' => 'http',
        ]);

        $body = $this->getJson('/api/v1/config')->assertOk()->json('data.realtime');

        // A bind address of localhost is useless to anything but this machine,
        // so the client is sent back to the host it just reached us on.
        $this->assertTrue($body['socket']['enabled']);
        $this->assertSame('ws://localhost:8080', $body['socket']['url']);
        $this->assertSame('test-key', $body['socket']['key']);
        $this->assertStringNotContainsString('test-secret', json_encode($body));
        $this->assertSame('/me/pulse', $body['pulse']['path']);
    }

    public function test_no_socket_is_advertised_when_none_is_configured(): void
    {
        $this->getJson('/api/v1/config')
            ->assertOk()
            ->assertJsonPath('data.realtime.socket.enabled', false)
            ->assertJsonPath('data.realtime.socket.url', '');
    }
}
