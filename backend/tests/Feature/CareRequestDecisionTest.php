<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The merged admin "Care requests & assignments" workspace.
 *
 * Approving a care request is the only path that creates a care assignment,
 * so these tests pin the three decisions the screen offers: approve as
 * requested, approve with a different provider (reason required), decline
 * (reason required).
 */
class CareRequestDecisionTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $patient;
    private CareProvider $requested;
    private CareProvider $alternative;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();

        $this->requested = CareProvider::create([
            'user_id' => User::factory()->role('doctor')->create()->id,
            'name' => 'Dr. Sarah Adeyemi',
            'specialty' => 'Endocrinology',
        ]);
        $this->alternative = CareProvider::create([
            'user_id' => User::factory()->role('doctor')->create()->id,
            'name' => 'Dr. Kojo Mensah',
            'specialty' => 'Cardiology',
        ]);

        Sanctum::actingAs($this->admin);
    }

    private function pendingRequest(): CareRequest
    {
        return CareRequest::create([
            'user_id' => $this->patient->id,
            'provider_id' => $this->requested->id,
            'provider_name' => $this->requested->name,
            'provider_specialty' => $this->requested->specialty,
            'reason' => 'New-patient diabetes consultation',
            'status' => 'pending',
        ]);
    }

    public function test_approving_assigns_the_requested_provider(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route", [
            'role' => 'Primary',
        ])->assertOk()
            ->assertJsonPath('data.care_request.status', 'approved')
            ->assertJsonPath('data.care_request.reassigned', false);

        $this->assertDatabaseHas('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->requested->id,
            'role' => 'Primary',
            'ended_at' => null,
        ]);
        $this->assertSame(
            $this->admin->id,
            $request->fresh()->decided_by,
        );
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $this->patient->id,
            'title' => 'Care request approved',
        ]);
    }

    public function test_re_routing_to_another_provider_requires_a_reason(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route", [
            'provider_id' => $this->alternative->id,
        ])->assertStatus(422);

        $this->assertSame('pending', $request->fresh()->status);
        $this->assertDatabaseCount('care_assignments', 0);
    }

    public function test_re_routing_assigns_the_chosen_provider_and_keeps_the_reason(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route", [
            'provider_id' => $this->alternative->id,
            'role' => 'Specialist',
            'note' => 'Closer facility and a matching specialty.',
        ])->assertOk()
            ->assertJsonPath('data.care_request.reassigned', true)
            ->assertJsonPath(
                'data.care_request.assigned_provider_name',
                'Dr. Kojo Mensah',
            );

        $this->assertDatabaseHas('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->alternative->id,
            'role' => 'Specialist',
            'assigned_reason' => 'Closer facility and a matching specialty.',
        ]);
        // The provider the patient asked for is not silently assigned too.
        $this->assertDatabaseMissing('care_assignments', [
            'provider_id' => $this->requested->id,
        ]);
    }

    public function test_a_doctor_can_be_identified_by_user_id(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route", [
            'provider_user_id' => $this->alternative->user_id,
            'note' => 'Requested doctor is at capacity.',
        ])->assertOk();

        $this->assertDatabaseHas('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->alternative->id,
        ]);
    }

    public function test_approving_an_already_paired_patient_updates_the_existing_row(): void
    {
        // Seeded / manually-created pairings must not be duplicated when the
        // patient later files a request for the same doctor.
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->requested->id,
            'role' => 'Primary',
            'assigned_at' => now()->subMonth(),
        ]);

        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route", [
            'role' => 'Consulting',
            'note' => 'Escalated to a consulting relationship.',
        ])->assertOk();

        $this->assertSame(1, CareAssignment::count());
        $this->assertDatabaseHas('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->requested->id,
            'role' => 'Consulting',
            'assigned_reason' => 'Escalated to a consulting relationship.',
            'assigned_by' => $this->admin->id,
        ]);
    }

    public function test_declining_records_the_reason_and_creates_no_assignment(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/cancel", [
            'reason' => 'Provider is not accepting new patients.',
        ])->assertOk()
            ->assertJsonPath('data.care_request.status', 'cancelled');

        $this->assertDatabaseCount('care_assignments', 0);
        $this->assertSame(
            'Provider is not accepting new patients.',
            $request->fresh()->decision_note,
        );
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $this->patient->id,
            'title' => 'Care request declined',
            'body' => 'Provider is not accepting new patients.',
        ]);
    }

    public function test_declining_without_a_reason_is_rejected(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/cancel", [])
            ->assertStatus(422);

        $this->assertSame('pending', $request->fresh()->status);
    }

    public function test_a_decided_request_cannot_be_decided_twice(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route")
            ->assertOk();
        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route")
            ->assertStatus(422);
        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/cancel", [
            'reason' => 'Changed my mind.',
        ])->assertStatus(422);

        $this->assertSame(1, CareAssignment::count());
        // Only the approval notification exists.
        $this->assertSame(1, AppNotification::where('kind', 'careRequest')->count());
    }

    public function test_index_exposes_the_decision_trail_and_filters_by_status(): void
    {
        $approved = $this->pendingRequest();
        $this->patchJson("/api/v1/admin/care-requests/{$approved->id}/route", [
            'provider_id' => $this->alternative->id,
            'note' => 'Better specialty match.',
        ])->assertOk();

        $this->pendingRequest();

        $this->getJson('/api/v1/admin/care-requests?status=pending')
            ->assertOk()
            ->assertJsonCount(1, 'data.care_requests');

        $rows = $this->getJson('/api/v1/admin/care-requests')
            ->assertOk()
            ->json('data.care_requests');

        $this->assertCount(2, $rows);
        $decided = collect($rows)->firstWhere('id', (string) $approved->id);
        $this->assertSame('Better specialty match.', $decided['decision_note']);
        $this->assertTrue($decided['reassigned']);
        $this->assertSame((string) $this->patient->id, $decided['patient_id']);
        $this->assertNotNull($decided['decided_at']);
    }

    public function test_assignment_can_be_ended_with_a_reason(): void
    {
        $request = $this->pendingRequest();
        $this->patchJson("/api/v1/admin/care-requests/{$request->id}/route")
            ->assertOk();

        $assignment = CareAssignment::firstOrFail();

        $this->deleteJson("/api/v1/admin/assignments/{$assignment->id}", [
            'reason' => 'Patient transferred to another facility.',
        ])->assertOk();

        $assignment->refresh();
        $this->assertNotNull($assignment->ended_at);
        $this->assertSame(
            'Patient transferred to another facility.',
            $assignment->ended_reason,
        );
        $this->assertSame($this->admin->id, $assignment->ended_by);

        // Ended pairings drop out of the default listing.
        $this->getJson('/api/v1/admin/assignments')
            ->assertOk()
            ->assertJsonCount(0, 'data.assignments');
    }
}
