<?php

namespace Tests\Feature;

use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Doctors do not triage care requests.
 *
 * A patient asking for a provider is a routing decision: admins and mCare
 * assistants holding `can_manage_care_requests` approve, re-route or decline
 * it, and approving is what creates the care assignment. A doctor sees the
 * care team they were assigned to — never the pending request itself.
 *
 * This file used to pin the opposite (a doctor accepting for themselves, and
 * the accept creating their own CareAssignment). That capability was removed;
 * these tests hold the boundary shut so it cannot come back by accident.
 * Admin routing stays covered by CareRequestDecisionTest.
 */
class DoctorCareRequestDecisionTest extends TestCase
{
    use RefreshDatabase;

    private User $doctor;
    private User $patient;
    private CareProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->doctor = User::factory()->role('doctor')->create();
        $this->patient = User::factory()->role('patient')->create();

        $this->provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => 'Dr. '.$this->doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);

        Sanctum::actingAs($this->doctor);
    }

    private function pendingRequest(): CareRequest
    {
        return CareRequest::create([
            'user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'provider_name' => $this->provider->name,
            'provider_specialty' => $this->provider->specialty,
            'reason' => 'Second opinion',
            'status' => 'pending',
        ]);
    }

    public function test_the_doctor_accept_endpoint_no_longer_exists(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/doctor/care-requests/{$request->id}/accept")
            ->assertNotFound();

        $this->assertDatabaseHas('care_requests', [
            'id' => $request->id,
            'status' => 'pending',
        ]);
    }

    public function test_the_doctor_decline_endpoint_no_longer_exists(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/doctor/care-requests/{$request->id}/decline", [
            'reason' => 'At capacity this month.',
        ])->assertNotFound();

        $this->assertDatabaseHas('care_requests', [
            'id' => $request->id,
            'status' => 'pending',
        ]);
    }

    /**
     * The decision is what creates the pairing, so a doctor who cannot decide
     * must not be able to put a patient on their own caseload either.
     */
    public function test_a_doctor_cannot_add_themselves_to_a_patients_care_team(): void
    {
        $request = $this->pendingRequest();

        $this->patchJson("/api/v1/doctor/care-requests/{$request->id}/accept");

        $this->assertDatabaseMissing('care_assignments', [
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
        ]);
    }

    public function test_a_pending_request_never_reaches_the_doctor_session(): void
    {
        $this->pendingRequest();

        $this->getJson('/api/v1/doctor/session')
            ->assertOk()
            ->assertJsonPath('data.care_requests', []);
    }

    /**
     * A doctor with no `care_providers` row must still get a clean session
     * rather than an error — the inbox is simply empty of requests for
     * everyone now, provider row or not.
     */
    public function test_a_doctor_with_no_provider_row_gets_an_empty_inbox_not_an_error(): void
    {
        $fresh = User::factory()->role('doctor')->create();
        Sanctum::actingAs($fresh);

        $this->getJson('/api/v1/doctor/session')
            ->assertOk()
            ->assertJsonPath('data.care_requests', []);
    }

    /**
     * Removing triage must not cost the doctor sight of the care team they
     * were actually assigned to — that is the half they keep.
     */
    public function test_an_assigned_patient_still_appears_in_the_caseload(): void
    {
        \App\Models\CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->doctor->id,
        ]);

        $ids = collect($this->getJson('/api/v1/doctor/session')->json('data.caseload'))
            ->pluck('id')
            ->all();

        $this->assertContains(
            (string) $this->patient->id,
            $ids,
            'an assigned patient is still the doctor\'s to see',
        );
    }
}
