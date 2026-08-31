<?php

namespace Tests\Feature;

use App\Models\Announcement;
use App\Models\MealPlan;
use App\Models\PatientReportRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The patient home feed rotates through announcements and assigned meals, so
 * the session payload has to carry both — and carry only what this patient is
 * allowed to see. An announcement written for doctors, one still in draft, or
 * one whose window has closed must never reach a patient's home screen, and a
 * meal plan belongs to exactly one patient.
 *
 * The session also carries outstanding requests to share the record. Consent
 * used to travel on a single notification, so a patient who read or missed it
 * had no route back to the approval screen and the request expired unanswered.
 */
class PatientHomeFeedPayloadTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;
    private User $other;
    private User $doctor;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->patient = User::factory()->role('patient')->create();
        $this->other = User::factory()->role('patient')->create();
        $this->doctor = User::factory()->role('doctor')->create();
    }

    private function meal(User $patient, string $title): MealPlan
    {
        return MealPlan::create([
            'patient_user_id' => $patient->id,
            'assigned_by_user_id' => $this->doctor->id,
            'title' => $title,
            'meal_type' => 'breakfast',
            'calories' => 320,
            'assigned_at' => now(),
        ]);
    }

    private function announcement(array $attributes): Announcement
    {
        return Announcement::create([
            'title' => 'Untitled',
            'body' => 'Body',
            'audience' => 'patients',
            'is_published' => true,
            'created_by_user_id' => $this->doctor->id,
            ...$attributes,
        ]);
    }

    public function test_session_carries_only_this_patients_meal_plans(): void
    {
        $mine = $this->meal($this->patient, 'Oats with berries');
        $this->meal($this->other, 'Someone else\'s lunch');

        Sanctum::actingAs($this->patient);
        $response = $this->getJson('/api/v1/patient/session')->assertOk();

        $meals = $response->json('data.meal_plans');
        $this->assertCount(1, $meals);
        $this->assertSame((string) $mine->id, $meals[0]['id']);
        $this->assertSame('Oats with berries', $meals[0]['title']);
        $this->assertSame(320, $meals[0]['calories']);
    }

    private function reportRequest(User $patient, array $attributes = []): PatientReportRequest
    {
        return PatientReportRequest::create([
            'patient_user_id' => $patient->id,
            'requested_by_user_id' => $this->doctor->id,
            'title' => 'Medical report',
            'purpose' => 'Insurance',
            'sections' => ['identity', 'health_profile'],
            'consent_required' => false,
            'signature_required' => true,
            'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE,
            ...$attributes,
        ]);
    }

    public function test_session_carries_this_patients_own_reports_only(): void
    {
        $mine = $this->reportRequest($this->patient);
        $this->reportRequest($this->other);

        Sanctum::actingAs($this->patient);
        $response = $this->getJson('/api/v1/patient/session')->assertOk();

        $consents = $response->json('data.report_consents');
        $this->assertCount(1, $consents, 'Only this patient\'s requests belong in the payload.');
        $this->assertSame((string) $mine->id, $consents[0]['id']);

        // Nothing here is ever the patient's move now: a doctor's signature
        // authorises a report, so the flag the home prompt and the More badge
        // read is always false. It stays in the payload so those two and the
        // screen keep reading one source rather than each deciding alone.
        $this->assertFalse($consents[0]['awaiting_me']);

        // Plain-language descriptions, so the patient reads what is disclosed.
        $this->assertCount(2, $consents[0]['section_details']);
        $this->assertArrayHasKey('label', $consents[0]['section_details'][0]);
    }

    public function test_session_does_not_mark_settled_requests_as_awaiting(): void
    {
        $this->reportRequest($this->patient, [
            'status' => PatientReportRequest::STATUS_ISSUED,
            'consented_at' => now()->subHour(),
        ]);
        // Expired challenges are no longer actionable either.
        $this->reportRequest($this->patient, [
            'consent_expires_at' => now()->subMinute(),
        ]);

        Sanctum::actingAs($this->patient);
        $response = $this->getJson('/api/v1/patient/session')->assertOk();

        $awaiting = array_filter(
            $response->json('data.report_consents'),
            fn (array $r) => $r['awaiting_me'] === true,
        );
        $this->assertSame([], array_values($awaiting));
    }

    public function test_session_carries_only_live_announcements_for_patients(): void
    {
        $forPatients = $this->announcement(['title' => 'Clinic hours extended']);
        $forEveryone = $this->announcement([
            'title' => 'Scheduled maintenance',
            'audience' => 'all',
        ]);
        $scheduled = $this->announcement([
            'title' => 'Opens next week',
            'starts_at' => now()->addWeek(),
        ]);
        $expired = $this->announcement([
            'title' => 'Last month',
            'ends_at' => now()->subDay(),
        ]);
        $draft = $this->announcement([
            'title' => 'Still a draft',
            'is_published' => false,
        ]);
        $forDoctors = $this->announcement([
            'title' => 'Rota change',
            'audience' => 'doctors',
        ]);

        Sanctum::actingAs($this->patient);
        $response = $this->getJson('/api/v1/patient/session')->assertOk();

        $titles = array_column($response->json('data.announcements'), 'title');

        $this->assertContains($forPatients->title, $titles);
        $this->assertContains($forEveryone->title, $titles);

        $this->assertNotContains($scheduled->title, $titles);
        $this->assertNotContains($expired->title, $titles);
        $this->assertNotContains($draft->title, $titles);
        $this->assertNotContains($forDoctors->title, $titles);
    }
}
