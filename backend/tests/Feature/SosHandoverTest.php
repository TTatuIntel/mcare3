<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AssistantPermission;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\SosEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Handing a live emergency to a provider.
 *
 * The handover used to run through the admin assignment CRUD, which refuses a
 * provider who is already assigned — so the patient's own care team, the
 * first thing the handover sheet offers, could never be chosen. It also left
 * the receiving provider uninformed: a care_assignments row is a scheduling
 * fact, not a summons. These pin both.
 */
class SosHandoverTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $patient;

    private User $doctor;

    private CareProvider $provider;

    private SosEvent $event;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();
        $this->doctor = User::factory()->role('doctor')->create();

        $this->provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => 'Dr. '.$this->doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);

        $this->event = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'location_label' => 'Nairobi, Westlands',
            'triggered_at' => now(),
        ]);
    }

    private function url(): string
    {
        return "/api/v1/admin/sos-events/{$this->event->id}/handover";
    }

    public function test_handing_over_assigns_records_and_takes_ownership(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated()
            ->assertJsonPath('data.action.action', 'assigned_provider')
            ->assertJsonPath('data.already_on_care_team', false)
            ->assertJsonPath('data.event.status', 'acknowledged');

        $this->assertDatabaseHas('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'ended_at' => null,
        ]);
        $this->assertDatabaseHas('sos_response_actions', [
            'sos_event_id' => $this->event->id,
            'action' => 'assigned_provider',
        ]);
        $this->assertSame(
            $this->provider->name,
            $this->event->fresh()->responded_by,
            'the emergency names whoever now holds it',
        );
    }

    public function test_the_care_team_can_be_handed_the_emergency(): void
    {
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);

        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated()
            ->assertJsonPath('data.already_on_care_team', true);

        $this->assertSame(
            1,
            CareAssignment::where('patient_user_id', $this->patient->id)
                ->where('provider_id', $this->provider->id)
                ->whereNull('ended_at')
                ->count(),
            'reusing the existing binding, not duplicating it',
        );
    }

    public function test_the_receiving_provider_is_notified(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated();

        $notification = AppNotification::where('user_id', $this->doctor->id)
            ->where('kind', 'sos')
            ->first();

        $this->assertNotNull($notification, 'a handover nobody is told about is not a handover');
        $this->assertSame((string) $this->event->id, $notification->action_arguments['event_id']);
        $this->assertSame('/doctor/sos', $notification->action_route);
    }

    public function test_the_handed_over_emergency_reaches_the_doctors_session(): void
    {
        Sanctum::actingAs($this->admin);
        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated();

        Sanctum::actingAs($this->doctor);
        $events = $this->getJson('/api/v1/doctor/session')
            ->assertOk()
            ->json('data.sos_events');

        $this->assertSame(
            [(string) $this->event->id],
            array_column($events, 'id'),
            'the provider taking over can actually see what they took over',
        );
    }

    public function test_a_doctor_can_follow_up_a_closed_emergency(): void
    {
        // The handover itself is what puts this patient on the doctor's
        // caseload — that is the case they then have to be able to follow.
        Sanctum::actingAs($this->admin);
        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated();

        Sanctum::actingAs($this->doctor);

        // Live list: the handover left it open and owned.
        $active = $this->getJson('/api/v1/doctor/sos')
            ->assertOk()
            ->json('data.sos_events');
        $this->assertCount(1, $active);
        $this->assertSame('acknowledged', $active[0]['status']);
        $this->assertNotEmpty(
            $active[0]['response_actions'],
            'the trail travels with the event so progress is visible without opening it',
        );

        // Closed, and therefore gone from the live list.
        $this->event->update(['status' => 'resolved', 'resolution' => 'patient_safe']);

        $this->assertSame(
            [],
            $this->getJson('/api/v1/doctor/sos')->assertOk()->json('data.sos_events'),
        );

        // But still reachable for follow-up, with how it ended.
        $all = $this->getJson('/api/v1/doctor/sos?status=all')
            ->assertOk()
            ->json('data.sos_events');
        $this->assertCount(1, $all);
        $this->assertSame('resolved', $all[0]['status']);
        $this->assertSame('Patient reached and safe', $all[0]['resolution_label']);
    }

    public function test_a_doctor_sees_no_emergency_outside_their_caseload(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->assertSame(
            [],
            $this->getJson('/api/v1/doctor/sos?status=all')->assertOk()->json('data.sos_events'),
        );
    }

    public function test_a_closed_emergency_cannot_be_handed_on(): void
    {
        $this->event->update(['status' => 'resolved']);
        Sanctum::actingAs($this->admin);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertStatus(409);

        $this->assertDatabaseCount('care_assignments', 0);
    }

    public function test_an_assistant_needs_both_grants(): void
    {
        $assistant = User::factory()->role('mcare_assistant')->create();
        AssistantPermission::create([
            'user_id' => $assistant->id,
            'permission_key' => 'can_access_emergency_location',
        ]);
        Sanctum::actingAs($assistant);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertStatus(403);

        AssistantPermission::create([
            'user_id' => $assistant->id,
            'permission_key' => 'can_assign_patients',
        ]);

        $this->postJson($this->url(), ['provider_id' => (string) $this->provider->id])
            ->assertCreated();
    }

    public function test_an_assistant_can_read_the_candidates_and_the_trail(): void
    {
        $assistant = User::factory()->role('mcare_assistant')->create();
        AssistantPermission::create([
            'user_id' => $assistant->id,
            'permission_key' => 'can_access_emergency_location',
        ]);
        Sanctum::actingAs($assistant);

        // `users.role` is `mcare_assistant`; the coordinator checks used to
        // match the client-facing `mcareAssistant` alias and refused every
        // assistant their own emergency screens.
        $this->getJson("/api/v1/admin/sos-events/{$this->event->id}/candidates")
            ->assertOk();

        $this->postJson("/api/v1/admin/sos-events/{$this->event->id}/actions", [
            'action' => 'called_patient',
        ])->assertCreated()
            ->assertJsonPath(
                'data.action.actor_name',
                $assistant->fullName().' (mCare Assistant)',
            );
    }
}
