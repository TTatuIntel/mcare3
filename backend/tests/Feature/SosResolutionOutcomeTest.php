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
 * How an emergency ended, and who could have taken it.
 *
 * "resolved" alone recorded a patient reached and safe, a patient carried out
 * by ambulance, and a patient nobody could reach in exactly the same way.
 * These pin that the outcome is named, that "other" cannot be used to dodge
 * saying what happened, and that a handover is offered care team first.
 */
class SosResolutionOutcomeTest extends TestCase
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
            'triggered_at' => now(),
        ]);

        Sanctum::actingAs($this->admin);
    }

    private function close(array $body)
    {
        return $this->patchJson("/api/v1/admin/sos-events/{$this->event->id}", $body);
    }

    public function test_closing_records_the_named_outcome(): void
    {
        $this->close([
            'status' => 'resolved',
            'resolution' => 'transported',
            'resolution_note' => 'Ambulance took her to Kenyatta.',
        ])->assertOk()
            ->assertJsonPath('data.event.resolution', 'transported')
            ->assertJsonPath('data.event.resolution_label', 'Transported to a facility');

        $this->assertDatabaseHas('sos_events', [
            'id' => $this->event->id,
            'status' => 'resolved',
            'resolution' => 'transported',
            'resolution_note' => 'Ambulance took her to Kenyatta.',
        ]);
    }

    public function test_other_without_words_is_refused(): void
    {
        $this->close(['status' => 'resolved', 'resolution' => 'other'])
            ->assertStatus(422);

        $this->assertDatabaseHas('sos_events', [
            'id' => $this->event->id,
            'status' => 'active',
        ]);
    }

    public function test_other_with_words_is_accepted(): void
    {
        $this->close([
            'status' => 'resolved',
            'resolution' => 'other',
            'resolution_note' => 'Neighbour drove her to the clinic herself.',
        ])->assertOk();

        $this->assertDatabaseHas('sos_events', [
            'id' => $this->event->id,
            'resolution' => 'other',
            'resolution_note' => 'Neighbour drove her to the clinic herself.',
        ]);
    }

    public function test_an_invented_outcome_is_refused(): void
    {
        $this->close(['status' => 'resolved', 'resolution' => 'made_up'])
            ->assertStatus(422);
    }

    public function test_acknowledging_never_stamps_an_outcome(): void
    {
        $this->close([
            'status' => 'acknowledged',
            'resolution' => 'patient_safe',
        ])->assertOk();

        $this->assertDatabaseHas('sos_events', [
            'id' => $this->event->id,
            'status' => 'acknowledged',
            'resolution' => null,
        ]);
    }

    public function test_handover_offers_the_care_team_first(): void
    {
        $teamDoctor = User::factory()->role('doctor')->create();
        $teamProvider = CareProvider::create([
            'user_id' => $teamDoctor->id,
            'name' => 'Dr. Care Team',
            'specialty' => 'Cardiology',
        ]);
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $teamProvider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);

        $stranger = User::factory()->role('doctor')->create();
        CareProvider::create([
            'user_id' => $stranger->id,
            'name' => 'Dr. Stranger',
            'specialty' => 'Neurology',
        ]);

        $body = $this->getJson(
            "/api/v1/admin/sos-events/{$this->event->id}/candidates"
        )->assertOk()->json('data');

        $this->assertSame(
            ['Dr. Care Team'],
            array_column($body['care_team'], 'name'),
            'the people who know the patient come first',
        );
        $this->assertContains('Dr. Stranger', array_column($body['others'], 'name'));
        $this->assertTrue($body['care_team'][0]['on_care_team']);
    }

    public function test_a_doctor_cannot_re_route_an_emergency(): void
    {
        $doctor = User::factory()->role('doctor')->create();
        Sanctum::actingAs($doctor);

        $this->getJson("/api/v1/admin/sos-events/{$this->event->id}/candidates")
            ->assertForbidden();
    }
}
