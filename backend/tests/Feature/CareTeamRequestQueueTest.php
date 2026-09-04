<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\DocumentRequest;
use App\Models\MedicalDocument;
use App\Models\User;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A request the patient raises is the whole care team's to see and exactly one
 * clinician's to do — and when it closes, it closes into something the patient
 * can open.
 */
class CareTeamRequestQueueTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;

    private User $drA;

    private User $drB;

    private User $outsider;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();
        $this->drA = User::factory()->role('doctor')->create();
        $this->drB = User::factory()->role('doctor')->create();
        $this->outsider = User::factory()->role('doctor')->create();

        foreach ([$this->drA, $this->drB] as $doctor) {
            $provider = CareProvider::create([
                'user_id' => $doctor->id,
                'name' => 'Dr. '.$doctor->fullName(),
                'specialty' => 'General practice',
            ]);
            CareAssignment::create([
                'patient_user_id' => $this->patient->id,
                'provider_id' => $provider->id,
                'role' => $doctor->is($this->drA) ? 'Primary' : 'Consulting',
                'assigned_at' => now(),
                'assigned_by' => $admin->id,
            ]);
        }

        CareProvider::create([
            'user_id' => $this->outsider->id,
            'name' => 'Dr. '.$this->outsider->fullName(),
            'specialty' => 'Dermatology',
        ]);
    }

    private function openVitalRequest(): VitalReportRequest
    {
        Sanctum::actingAs($this->patient);

        return VitalReportRequest::findOrFail(
            $this->postJson('/api/v1/patient/vital-report-requests', [
                'range_from' => now()->subDays(14)->toDateString(),
                'range_to' => now()->toDateString(),
                'vitals' => ['heartRate'],
                'note' => 'For my cardiology follow-up',
            ])->assertCreated()->json('data.request.id')
        );
    }

    // -----------------------------------------------------------------
    // Vital report requests
    // -----------------------------------------------------------------

    public function test_every_assigned_clinician_sees_the_request_and_outsiders_do_not(): void
    {
        $this->openVitalRequest();

        foreach ([$this->drA, $this->drB] as $doctor) {
            Sanctum::actingAs($doctor);
            $rows = $this->getJson('/api/v1/doctor/vital-report-requests')
                ->assertOk()
                ->json('data.requests');

            $this->assertCount(1, $rows);
            $this->assertTrue($rows[0]['claimable']);
            $this->assertFalse($rows[0]['claimed_by_me']);
        }

        Sanctum::actingAs($this->outsider);
        $this->assertCount(
            0,
            $this->getJson('/api/v1/doctor/vital-report-requests')->json('data.requests'),
        );
    }

    public function test_only_one_clinician_can_hold_a_request(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")
            ->assertOk()
            ->assertJsonPath('data.request.claimed_by_me', true)
            ->assertJsonPath('data.request.status', VitalReportRequest::IN_PROGRESS);

        // The second clinician is not errored at so much as told who has it.
        Sanctum::actingAs($this->drB);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")
            ->assertStatus(409)
            ->assertJsonPath('data.request.claimed_by_me', false)
            ->assertJsonPath('data.request.claimable', false);

        $this->assertSame($this->drA->id, $request->fresh()->claimed_by);
    }

    public function test_a_clinician_cannot_complete_a_request_a_colleague_holds(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();

        Sanctum::actingAs($this->drB);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/fulfill", [
            'note' => 'Looks fine to me',
        ])->assertStatus(409);

        $this->assertSame(VitalReportRequest::IN_PROGRESS, $request->fresh()->status);
        $this->assertNull($request->fresh()->document_id);
    }

    public function test_a_released_request_returns_to_the_queue(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/release", [
            'note' => 'Off shift',
        ])->assertOk();

        Sanctum::actingAs($this->drB);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")
            ->assertOk()
            ->assertJsonPath('data.request.claimed_by_me', true);
    }

    public function test_releasing_is_refused_to_anyone_but_the_holder(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();

        Sanctum::actingAs($this->drB);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/release")
            ->assertStatus(403);

        $this->assertSame($this->drA->id, $request->fresh()->claimed_by);
    }

    public function test_fulfilling_files_a_vital_report_the_patient_can_open(): void
    {
        Storage::fake('local');

        VitalReading::create([
            'user_id' => $this->patient->id,
            'vital_key' => 'heartRate',
            'value' => 72,
            'risk' => 'normal',
            'recorded_at' => now()->subDays(3),
        ]);
        VitalReading::create([
            'user_id' => $this->patient->id,
            'vital_key' => 'heartRate',
            'value' => 96,
            'risk' => 'warning',
            'recorded_at' => now()->subDay(),
        ]);

        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/fulfill", [
            'note' => 'Rate is settled; keep logging mornings.',
        ])->assertOk()->assertJsonPath('data.request.status', VitalReportRequest::FULFILLED);

        $request->refresh();
        $this->assertNotNull($request->document_id);
        $this->assertNotNull($request->resolved_at);

        $document = MedicalDocument::findOrFail($request->document_id);
        $this->assertSame('vitalReport', $document->category);
        $this->assertSame(MedicalDocument::SOURCE_REPORT, $document->source);
        $this->assertSame($this->patient->id, $document->user_id);

        // It shows up where the patient was told to look, and the numbers in
        // it are the ones recorded in the window.
        Sanctum::actingAs($this->patient);
        $listed = collect(
            $this->getJson('/api/v1/patient/documents')->assertOk()->json('data.documents')
        )->firstWhere('category', 'vitalReport');
        $this->assertNotNull($listed);

        $body = $this->get("/api/v1/patient/documents/{$document->id}/stream")
            ->assertOk()
            ->streamedContent();
        $this->assertStringContainsString('Heart Rate', $body);
        $this->assertStringContainsString('Rate is settled', $body);
        $this->assertStringContainsString('50%', $body); // one of two readings in range
    }

    public function test_the_trail_records_who_did_what(): void
    {
        Storage::fake('local');
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/fulfill")->assertOk();

        Sanctum::actingAs($this->patient);
        $actions = collect(
            $this->getJson('/api/v1/patient/vital-report-requests')
                ->assertOk()
                ->json('data.requests.0.events')
        )->pluck('action')->all();

        $this->assertSame(['opened', 'claimed', 'resolved'], $actions);
    }

    public function test_escalation_hands_the_request_back_rather_than_keeping_the_claim(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/escalate")->assertOk();

        $request->refresh();
        $this->assertNull($request->claimed_by);
        $this->assertSame('admin', $request->current_responder);
        $this->assertSame(VitalReportRequest::PENDING, $request->status);
    }

    public function test_the_sla_clock_skips_a_request_somebody_has_taken_on(): void
    {
        $claimed = $this->openVitalRequest();
        $ignored = $this->openVitalRequest();

        // Both are two days old; only one has anybody on it.
        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$claimed->id}/claim")
            ->assertOk();

        foreach ([$claimed, $ignored] as $r) {
            $r->forceFill(['created_at' => now()->subHours(60)])->saveQuietly();
        }

        $this->artisan('vitals:escalate-report-requests')->assertSuccessful();

        // Escalating work a clinician is mid-way through would send an admin
        // to chase someone who is already doing it.
        $this->assertSame('doctor', $claimed->fresh()->current_responder);
        $this->assertSame('mcareAssistant', $ignored->fresh()->current_responder);

        // And the patient's trail says why the untouched one moved.
        $this->assertSame(
            ['opened', 'escalated'],
            $ignored->fresh()->events->pluck('action')->all(),
        );
    }

    public function test_a_cancelled_request_cannot_then_be_worked_on(): void
    {
        $request = $this->openVitalRequest();

        Sanctum::actingAs($this->patient);
        $this->patchJson("/api/v1/patient/vital-report-requests/{$request->id}")->assertOk();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")
            ->assertStatus(422);
    }

    // -----------------------------------------------------------------
    // Document requests
    // -----------------------------------------------------------------

    private function openDocumentRequest(array $overrides = []): DocumentRequest
    {
        Sanctum::actingAs($this->patient);

        return DocumentRequest::findOrFail(
            $this->postJson('/api/v1/patient/document-requests', array_merge([
                'title' => 'Referral letter for physiotherapy',
                'category' => 'referral',
                'target' => 'team',
                'note' => 'The clinic needs it before my first session.',
            ], $overrides))->assertCreated()->json('data.request.id')
        );
    }

    public function test_a_patient_can_ask_the_team_and_the_whole_team_sees_it(): void
    {
        $this->openDocumentRequest();

        foreach ([$this->drA, $this->drB] as $doctor) {
            Sanctum::actingAs($doctor);
            $rows = $this->getJson('/api/v1/doctor/document-requests')->assertOk()->json('data.requests');
            $this->assertCount(1, $rows);
            $this->assertTrue($rows[0]['claimable']);
        }
    }

    public function test_naming_a_doctor_still_leaves_it_visible_to_the_team(): void
    {
        $this->openDocumentRequest([
            'target' => 'doctor',
            'target_doctor_id' => $this->drA->id,
        ]);

        Sanctum::actingAs($this->drB);
        $rows = $this->getJson('/api/v1/doctor/document-requests')->assertOk()->json('data.requests');
        $this->assertCount(1, $rows);
        $this->assertFalse($rows[0]['addressed_to_me']);

        Sanctum::actingAs($this->drA);
        $rows = $this->getJson('/api/v1/doctor/document-requests')->json('data.requests');
        $this->assertTrue($rows[0]['addressed_to_me']);
    }

    public function test_a_doctor_outside_the_care_team_cannot_be_named(): void
    {
        Sanctum::actingAs($this->patient);

        $this->postJson('/api/v1/patient/document-requests', [
            'title' => 'Sick note',
            'category' => 'other',
            'target' => 'doctor',
            'target_doctor_id' => $this->outsider->id,
        ])->assertStatus(422);
    }

    public function test_fulfilling_a_document_request_files_the_document_and_closes_it(): void
    {
        Storage::fake('local');
        $request = $this->openDocumentRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/document-requests/{$request->id}/claim")->assertOk();

        $this->post("/api/v1/doctor/document-requests/{$request->id}/fulfill", [
            'title' => 'Physiotherapy referral',
            'category' => 'referral',
            'file_type' => 'pdf',
            'note' => 'Sent to the clinic as well.',
            'file' => UploadedFile::fake()->create('referral.pdf', 12, 'application/pdf'),
        ])->assertCreated();

        $request->refresh();
        $this->assertSame(DocumentRequest::FULFILLED, $request->status);
        $this->assertNotNull($request->document_id);

        $document = MedicalDocument::findOrFail($request->document_id);
        $this->assertSame($this->patient->id, $document->user_id);
        $this->assertSame(MedicalDocument::SOURCE_CLINICIAN, $document->source);

        Sanctum::actingAs($this->patient);
        $this->assertNotNull(collect(
            $this->getJson('/api/v1/patient/documents')->json('data.documents')
        )->firstWhere('title', 'Physiotherapy referral'));
    }

    public function test_declining_needs_a_reason_the_patient_can_read(): void
    {
        $request = $this->openDocumentRequest();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/document-requests/{$request->id}/decline")
            ->assertStatus(422);

        $this->patchJson("/api/v1/doctor/document-requests/{$request->id}/decline", [
            'reason' => 'This record is held by your previous practice, not us.',
        ])->assertOk();

        Sanctum::actingAs($this->patient);
        $row = $this->getJson('/api/v1/patient/document-requests')->json('data.requests.0');
        $this->assertSame(DocumentRequest::DECLINED, $row['status']);
        $this->assertStringContainsString('previous practice', $row['decline_reason']);
    }

    public function test_a_patient_can_withdraw_a_request_before_it_is_answered(): void
    {
        $request = $this->openDocumentRequest();

        Sanctum::actingAs($this->patient);
        $this->deleteJson("/api/v1/patient/document-requests/{$request->id}")->assertOk();

        Sanctum::actingAs($this->drA);
        $this->patchJson("/api/v1/doctor/document-requests/{$request->id}/claim")
            ->assertStatus(422);
    }
}
