<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\SosEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * What happens to everyone else when a clinician closes an alert.
 *
 * Resolving used to be a private act: the reason was filed where only staff
 * would read it, the patient watched the red card disappear without ever
 * being told why, a second alert about the same reading stayed open for the
 * next clinician to chase, and an emergency behind an alert stayed live on
 * the SOS console after the alert itself was cleared. These pin the whole
 * conversation — the outcome, who decided it, who hears it, and what goes
 * quiet.
 */
class AlertResolutionCommunicationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $patient;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->admin = User::factory()->role('admin')->create([
            'first_name' => 'Grace',
            'last_name' => 'Otieno',
        ]);
        $this->patient = User::factory()->role('patient')->create();

        Sanctum::actingAs($this->admin);
    }

    private function vitalAlert(array $overrides = []): AppNotification
    {
        return AppNotification::create(array_merge([
            'user_id' => $this->patient->id,
            'kind' => 'vital_critical',
            'title' => 'Heart rate is critical',
            'body' => '39 bpm recorded at 2:45 PM',
            'action_route' => '/patient/vitals',
            'action_arguments' => ['vital_key' => 'heartRate', 'value' => 39],
            'read' => false,
            'resolved' => false,
        ], $overrides));
    }

    private function resolve(AppNotification $alert, array $body)
    {
        return $this->patchJson("/api/v1/admin/alerts/{$alert->id}/resolve", $body);
    }

    public function test_the_patient_is_told_who_closed_the_alert_and_why(): void
    {
        $alert = $this->vitalAlert();

        $this->resolve($alert, [
            'action_taken' => 'patient_contacted',
            'note' => 'Spoke with her, resting and stable. Recheck at 6pm.',
        ])->assertOk();

        $told = AppNotification::where('user_id', $this->patient->id)
            ->where('kind', 'alert_resolved')
            ->first();

        $this->assertNotNull($told, 'the patient hears nothing when nobody writes to them');
        $this->assertStringContainsString('Grace Otieno (Care admin)', $told->body);
        $this->assertStringContainsString('Patient contacted', $told->body);
        $this->assertStringContainsString('resting and stable', $told->body);
        $this->assertSame('heart rate alert resolved', strtolower($told->title));
    }

    public function test_the_closed_alert_carries_the_outcome_and_the_responder(): void
    {
        $alert = $this->vitalAlert();

        $body = $this->resolve($alert, [
            'action_taken' => 'other',
            'custom_action' => 'Cuff refitted and re-measured',
            'note' => 'Sleeve was bunched under the cuff.',
        ])->assertOk()->json('data.alert');

        $this->assertTrue($body['resolved']);

        $args = $alert->fresh()->action_arguments;
        $this->assertSame('other', $args['resolution_action']);
        $this->assertSame('Cuff refitted and re-measured', $args['resolution_custom_action']);
        $this->assertSame('Sleeve was bunched under the cuff.', $args['resolution_note']);
        $this->assertSame('Grace Otieno (Care admin)', $args['resolved_by']);
        $this->assertSame($this->admin->id, $args['resolved_by_user_id']);
    }

    public function test_the_same_outcome_closes_every_open_alert_about_that_vital(): void
    {
        $older = $this->vitalAlert(['kind' => 'vital_warning', 'title' => 'Heart rate elevated']);
        $worked = $this->vitalAlert();
        $unrelated = $this->vitalAlert([
            'kind' => 'vital_warning',
            'title' => 'Blood oxygen low',
            'action_arguments' => ['vital_key' => 'bloodOxygen', 'value' => 91],
        ]);

        $this->resolve($worked, [
            'action_taken' => 'monitored',
            'note' => 'Reviewed the trace, watching for an hour.',
        ])->assertOk();

        $older = $older->fresh();
        $this->assertTrue($older->resolved, 'a duplicate left open sends the next clinician after the same problem');
        $this->assertSame('monitored', $older->action_arguments['resolution_action']);
        $this->assertSame((string) $worked->id, $older->action_arguments['superseded_by_alert_id']);

        $this->assertFalse(
            $unrelated->fresh()->resolved,
            'a different vital is a different problem and must stay open',
        );
    }

    public function test_acknowledging_records_the_responder_without_closing_anything(): void
    {
        $alert = $this->vitalAlert();

        $this->patchJson("/api/v1/admin/alerts/{$alert->id}/acknowledge")->assertOk();

        $alert = $alert->fresh();
        $this->assertTrue($alert->read);
        $this->assertFalse($alert->resolved, 'seeing an alert is not dealing with it');
        $this->assertSame('Grace Otieno (Care admin)', $alert->action_arguments['acknowledged_by']);

        $this->assertSame(
            0,
            AppNotification::where('user_id', $this->patient->id)
                ->where('kind', 'alert_resolved')
                ->count(),
            'nothing has been decided yet, so there is nothing to tell the patient',
        );
    }

    public function test_an_acknowledged_alert_stays_on_the_open_list(): void
    {
        $alert = $this->vitalAlert();
        $this->patchJson("/api/v1/admin/alerts/{$alert->id}/acknowledge")->assertOk();

        $open = $this->getJson('/api/v1/admin/alerts?open_only=1')
            ->assertOk()
            ->json('data.alerts');

        $this->assertSame([(string) $alert->id], array_column($open, 'id'));
    }

    public function test_closing_an_emergency_alert_closes_the_emergency_behind_it(): void
    {
        $event = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'fall',
            'status' => 'active',
            'triggered_at' => now(),
        ]);
        $patientCopy = AppNotification::create([
            'user_id' => $this->patient->id,
            'kind' => 'sos',
            'title' => 'Emergency SOS activated',
            'body' => 'Fall',
            'action_route' => '/patient/sos',
            'action_arguments' => ['event_id' => (string) $event->id],
            'read' => false,
            'resolved' => false,
        ]);
        $careTeamCopy = AppNotification::create([
            'user_id' => $this->admin->id,
            'kind' => 'sos',
            'title' => 'SOS · patient',
            'body' => 'Fall',
            'action_route' => '/admin/sos',
            'action_arguments' => [
                'event_id' => (string) $event->id,
                'patient_id' => (string) $this->patient->id,
            ],
            'read' => false,
            'resolved' => false,
        ]);

        $this->resolve($patientCopy, [
            'action_taken' => 'patient_contacted',
            'note' => 'Reached him by phone, no injury, neighbour is with him.',
        ])->assertOk();

        $event = $event->fresh();
        $this->assertSame('resolved', $event->status, 'the SOS console must not keep showing a handled emergency');
        $this->assertSame('patient_safe', $event->resolution);
        $this->assertSame('Grace Otieno (Care admin)', $event->responded_by);

        $this->assertTrue($careTeamCopy->fresh()->resolved, 'the care team keeps being paged about a closed emergency');
    }

    public function test_closing_one_emergency_leaves_another_alone(): void
    {
        $first = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'fall',
            'status' => 'active',
            'triggered_at' => now()->subHour(),
        ]);
        $second = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'triggered_at' => now(),
        ]);

        $secondAlert = AppNotification::create([
            'user_id' => $this->admin->id,
            'kind' => 'sos',
            'title' => 'SOS · patient',
            'body' => 'Medical emergency',
            'action_arguments' => ['event_id' => (string) $second->id],
            'read' => false,
            'resolved' => false,
        ]);

        $this->patchJson("/api/v1/admin/sos-events/{$first->id}", [
            'status' => 'resolved',
            'resolution' => 'patient_safe',
        ])->assertOk();

        $this->assertFalse(
            $secondAlert->fresh()->resolved,
            'a second live emergency must not be cleared by closing the first',
        );
    }

    public function test_a_resolved_emergency_tells_the_patient_the_named_outcome(): void
    {
        $event = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'triggered_at' => now(),
        ]);

        $this->patchJson("/api/v1/admin/sos-events/{$event->id}", [
            'status' => 'resolved',
            'resolution' => 'transported',
            'resolution_note' => 'Ambulance took you to Kenyatta.',
        ])->assertOk();

        $told = AppNotification::where('user_id', $this->patient->id)
            ->where('kind', 'sos_resolved')
            ->firstOrFail();

        $this->assertStringContainsString('Grace Otieno (Care admin)', $told->body);
        $this->assertStringContainsString('Transported to a facility', $told->body);
        $this->assertStringContainsString('Ambulance took you to Kenyatta.', $told->body);
        $this->assertSame('transported', $told->action_arguments['resolution']);
    }

    public function test_acknowledging_an_emergency_keeps_the_care_team_paged(): void
    {
        $event = SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'panic',
            'status' => 'active',
            'triggered_at' => now(),
        ]);
        $careTeamCopy = AppNotification::create([
            'user_id' => $this->admin->id,
            'kind' => 'sos',
            'title' => 'SOS · patient',
            'body' => 'Panic',
            'action_arguments' => ['event_id' => (string) $event->id],
            'read' => false,
            'resolved' => false,
        ]);

        $this->patchJson("/api/v1/admin/sos-events/{$event->id}", [
            'status' => 'acknowledged',
        ])->assertOk();

        $this->assertFalse(
            $careTeamCopy->fresh()->resolved,
            'one responder saying "I am on it" must not take a live emergency off every other console',
        );
    }
}
