<?php

namespace Tests\Feature;

use App\Models\MedicalDocument;
use App\Models\User;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * An escalated request somebody can actually finish.
 *
 * The queue escalates on its own — doctor for 48 hours, then mCare assistant,
 * then admin — and escalated into nothing. Those tiers had no claim route and
 * no fulfil route, so a request that aged past its first window was handed to
 * people who could not act on it: the patient waited on a report nobody was
 * able to produce, and it sat at the top of the queue as the oldest thing in it
 * forever. The escalation was real and the destination was a dead end.
 */
class EscalatedVitalReportQueueTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;

    private User $admin;

    private VitalReportRequest $request;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Storage::fake('local');

        $this->patient = User::factory()->role('patient')->create();
        $this->admin = User::factory()->role('admin')->create();

        VitalReading::create([
            'user_id' => $this->patient->id,
            'vital_key' => 'heartRate',
            'value' => 72,
            'risk' => 'normal',
            'recorded_at' => now()->subDays(3),
        ]);

        // Aged past the doctor tier, exactly as the escalation command leaves it.
        $this->request = VitalReportRequest::create([
            'user_id' => $this->patient->id,
            'range_from' => now()->subDays(30),
            'range_to' => now(),
            'vitals' => ['heartRate'],
            'note' => 'For my cardiology follow-up',
            'status' => VitalReportRequest::PENDING,
            'current_responder' => 'admin',
            'last_escalated_at' => now()->subDay(),
        ]);
    }

    public function test_admin_staff_see_the_queue_they_are_escalated_into(): void
    {
        Sanctum::actingAs($this->admin);

        $response = $this->getJson('/api/v1/admin/vital-report-requests');

        $response->assertOk();
        // They have no caseload — scoping them to one would hide exactly the
        // requests these tiers exist to pick up.
        $this->assertContains(
            (string) $this->request->id,
            collect($response->json('data.requests'))->pluck('id')->all(),
        );
    }

    public function test_admin_staff_can_finish_an_escalated_request(): void
    {
        Sanctum::actingAs($this->admin);

        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/claim")
            ->assertOk();

        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/fulfill", [
            'note' => 'Reviewed; readings are stable.',
        ])->assertOk();

        $fresh = $this->request->fresh();
        $this->assertSame(VitalReportRequest::FULFILLED, $fresh->status);
        $this->assertNotNull(
            $fresh->document_id,
            'Finishing a request must leave the patient a report to open.',
        );

        $document = MedicalDocument::find($fresh->document_id);
        $this->assertSame('vitalReport', $document->category);
        $this->assertSame('text/html', $document->mime_type);
    }

    public function test_the_patient_can_open_what_the_admin_signed(): void
    {
        Sanctum::actingAs($this->admin);
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/fulfill")->assertOk();

        $documentId = $this->request->fresh()->document_id;

        Sanctum::actingAs($this->patient);

        $listed = $this->getJson('/api/v1/patient/documents');
        $listed->assertOk();
        $this->assertContains(
            (string) $documentId,
            collect($listed->json('data.documents'))->pluck('id')->all(),
        );

        $streamed = $this->get("/api/v1/patient/documents/{$documentId}/stream");
        $streamed->assertOk();
        $this->assertStringStartsWith('text/html', $streamed->headers->get('Content-Type'));
    }

    public function test_the_signature_names_the_staff_member_who_signed(): void
    {
        Sanctum::actingAs($this->admin);
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/claim")->assertOk();
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/fulfill")->assertOk();

        $fresh = $this->request->fresh();

        // Fulfilling is signing, whoever does it. A report that reached the
        // patient unsigned, or signed by a role it did not come from, is the
        // worse failure by a distance.
        $this->assertSame('admin', $fresh->signed_by_role);
        $this->assertStringContainsString('mCare admin', (string) $fresh->signed_by);
        $this->assertNotNull($fresh->signed_at);
    }

    public function test_a_patient_cannot_work_the_staff_queue(): void
    {
        Sanctum::actingAs($this->patient);

        $this->getJson('/api/v1/admin/vital-report-requests')->assertForbidden();
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/fulfill")
            ->assertForbidden();
    }

    public function test_two_staff_cannot_both_hold_one_request(): void
    {
        $other = User::factory()->role('admin')->create();

        Sanctum::actingAs($this->admin);
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/claim")->assertOk();

        Sanctum::actingAs($other);
        // Losing the race is a normal outcome, and the loser is told who holds
        // it rather than being allowed to write a second report.
        $this->patchJson("/api/v1/admin/vital-report-requests/{$this->request->id}/claim")
            ->assertStatus(409);
    }
}
