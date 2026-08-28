<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\SosEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * How an emergency was worked, not just who ended it.
 *
 * A status change records the outcome and nothing else, so a responder who
 * called the patient, pulled their location and handed the case over left no
 * trace of any of it. A handover mid-emergency, or any review afterwards,
 * started from nothing. These pin that the trail survives, that it is
 * append-only, and that it is not readable by people outside the response.
 */
class SosResponseTrailTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $patient;
    private SosEvent $event;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();

        $this->event = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'location_label' => 'Nairobi, Westlands',
            'triggered_at' => now(),
        ]);
    }

    private function url(string $suffix = ''): string
    {
        return "/api/v1/admin/sos-events/{$this->event->id}/actions{$suffix}";
    }

    public function test_a_responder_can_record_what_they_did(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), [
            'action' => 'called_patient',
            'detail' => 'No answer on the first attempt.',
        ])->assertCreated()
            ->assertJsonPath('data.action.action', 'called_patient')
            ->assertJsonPath('data.action.label', 'Called the patient');

        $this->assertDatabaseHas('sos_response_actions', [
            'sos_event_id' => $this->event->id,
            'user_id' => $this->admin->id,
            'action' => 'called_patient',
            'detail' => 'No answer on the first attempt.',
        ]);
    }

    public function test_the_trail_survives_and_reads_in_order(): void
    {
        Sanctum::actingAs($this->admin);

        foreach (['called_patient', 'viewed_location', 'took_ownership'] as $step) {
            $this->postJson($this->url(), ['action' => $step])->assertCreated();
        }

        $actions = $this->getJson($this->url())
            ->assertOk()
            ->json('data.actions');

        $this->assertSame(
            ['called_patient', 'viewed_location', 'took_ownership'],
            array_column($actions, 'action'),
            'the trail is the order the work happened in',
        );
        $this->assertNotEmpty(
            $actions[0]['actor_name'],
            'a trail with no author cannot be handed over',
        );
    }

    public function test_the_trail_rides_along_with_the_sos_list(): void
    {
        Sanctum::actingAs($this->admin);
        $this->postJson($this->url(), ['action' => 'opened_chart'])->assertCreated();

        $events = $this->getJson('/api/v1/admin/sos-events?status=active')
            ->assertOk()
            ->json('data.sos_events');

        $this->assertCount(1, $events[0]['response_actions']);
        $this->assertSame('opened_chart', $events[0]['response_actions'][0]['action']);
    }

    public function test_a_closed_emergency_stops_accepting_steps(): void
    {
        Sanctum::actingAs($this->admin);
        $this->event->update(['status' => 'resolved']);

        $this->postJson($this->url(), ['action' => 'called_patient'])
            ->assertStatus(409);

        $this->assertDatabaseCount('sos_response_actions', 0);
    }

    public function test_an_unknown_step_is_refused(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), ['action' => 'whatever'])
            ->assertStatus(422);
    }

    public function test_a_doctor_outside_the_caseload_cannot_read_the_trail(): void
    {
        $doctor = User::factory()->role('doctor')->create();
        CareProvider::create([
            'user_id' => $doctor->id,
            'name' => 'Dr. '.$doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);
        Sanctum::actingAs($doctor);

        $this->getJson("/api/v1/doctor/sos/{$this->event->id}/actions")
            ->assertStatus(403);
    }

    public function test_a_doctor_on_the_caseload_can_work_the_trail(): void
    {
        $doctor = User::factory()->role('doctor')->create();
        $provider = CareProvider::create([
            'user_id' => $doctor->id,
            'name' => 'Dr. '.$doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $doctor->id,
        ]);
        Sanctum::actingAs($doctor);

        $this->postJson("/api/v1/doctor/sos/{$this->event->id}/actions", [
            'action' => 'called_patient',
        ])->assertCreated();

        $this->getJson("/api/v1/doctor/sos/{$this->event->id}/actions")
            ->assertOk()
            ->assertJsonPath('data.actions.0.action', 'called_patient');
    }

    public function test_a_patient_cannot_read_their_own_response_trail(): void
    {
        Sanctum::actingAs($this->patient);

        $this->getJson("/api/v1/doctor/sos/{$this->event->id}/actions")
            ->assertStatus(403);
    }
}
