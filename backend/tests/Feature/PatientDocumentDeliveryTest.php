<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MedicalDocument;
use App\Models\PatientReportRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Getting a document to the patient it belongs to.
 *
 * Three things were broken. A doctor could file a document and the patient was
 * never told, so a lab result sat unread until they happened to scroll their
 * documents list. Admin staff could not file one at all, which pushed the
 * paperwork that is not a doctor's to send — insurance letters, scanned
 * consents — out of the audited store and into email. And an issued report,
 * the one document assembled *from* the patient's own record, exposed nothing
 * but `has_snapshot: true`: the person it described was the only party who
 * could not read what had been disclosed about them.
 */
class PatientDocumentDeliveryTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;
    private User $admin;
    private User $doctor;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Storage::fake('local');

        $this->patient = User::factory()->role('patient')->create();
        $this->admin = User::factory()->role('admin')->create();
        $this->doctor = User::factory()->role('doctor')->create();
    }

    public function test_admin_can_send_a_document_to_a_patient(): void
    {
        Sanctum::actingAs($this->admin);

        $response = $this->postJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents",
            [
                'title' => 'Insurance clearance letter',
                'category' => 'other',
                'file_type' => 'pdf',
                'description' => 'For your records.',
                'file' => UploadedFile::fake()->create('clearance.pdf', 24, 'application/pdf'),
            ],
        );

        $response->assertCreated();

        $document = MedicalDocument::where('user_id', $this->patient->id)->first();
        $this->assertNotNull($document);
        $this->assertSame('Insurance clearance letter', $document->title);
        // The patient reads this line to answer "who sent me this?".
        $this->assertStringContainsString('mCare admin', $document->uploaded_by);
    }

    public function test_a_document_from_admin_notifies_the_patient(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/documents", [
            'title' => 'Discharge summary',
            'category' => 'discharge',
            'file_type' => 'pdf',
            'file' => UploadedFile::fake()->create('d.pdf', 12, 'application/pdf'),
        ])->assertCreated();

        $note = AppNotification::where('user_id', $this->patient->id)
            ->where('kind', 'document')
            ->first();

        $this->assertNotNull($note, 'The patient was never told a document arrived.');
        $this->assertStringContainsString('Discharge summary', $note->body);
        // Plain words, not the camelCase enum key.
        $this->assertStringContainsString('discharge summary', $note->body);
        $this->assertSame('/patient/documents', $note->action_route);
    }

    public function test_a_document_from_a_doctor_notifies_the_patient(): void
    {
        $this->attachDoctorToPatient();
        Sanctum::actingAs($this->doctor);

        $this->postJson("/api/v1/doctor/patients/{$this->patient->id}/documents", [
            'title' => 'Blood panel',
            'category' => 'labResult',
            'file_type' => 'pdf',
            'file' => UploadedFile::fake()->create('panel.pdf', 10, 'application/pdf'),
        ])->assertCreated();

        $note = AppNotification::where('user_id', $this->patient->id)
            ->where('kind', 'document')
            ->first();

        $this->assertNotNull($note);
        $this->assertStringContainsString('Blood panel', $note->body);
        $this->assertStringContainsString('Dr.', $note->title);
    }

    public function test_admin_cannot_touch_a_document_belonging_to_someone_else(): void
    {
        $other = User::factory()->role('patient')->create();
        $document = MedicalDocument::create([
            'user_id' => $other->id,
            'title' => 'Not yours',
            'category' => 'other',
            'file_type' => 'pdf',
            'uploaded_by' => 'someone',
            'uploaded_at' => now(),
        ]);

        Sanctum::actingAs($this->admin);

        // Addressed through the wrong patient, the document must not resolve.
        $this->getJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}/stream"
        )->assertNotFound();

        // The delete verb exists now — it is how staff honour a removal the
        // patient asked for — but addressed through the wrong patient it must
        // not resolve either. What may and may not be deleted is covered in
        // ReportIssueAndRecordProtectionTest.
        $this->deleteJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertNotFound();

        $this->assertDatabaseHas('medical_documents', ['id' => $document->id]);
    }

    public function test_a_patient_cannot_reach_the_admin_document_routes(): void
    {
        Sanctum::actingAs($this->patient);

        $this->getJson("/api/v1/admin/patients/{$this->patient->id}/documents")
            ->assertForbidden();
    }

    public function test_a_patient_can_list_their_documents_without_the_session(): void
    {
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/documents", [
            'title' => 'Discharge summary',
            'category' => 'discharge',
            'file_type' => 'pdf',
            'file' => UploadedFile::fake()->create('d.pdf', 12, 'application/pdf'),
        ])->assertCreated();

        // The notification announcing a document routes to the documents
        // screen, so that screen has to be able to fetch it on its own rather
        // than wait for the next full session sync.
        Sanctum::actingAs($this->patient);
        $documents = $this->getJson('/api/v1/patient/documents')
            ->assertOk()
            ->json('data.documents');

        $this->assertCount(1, $documents);
        $this->assertSame('Discharge summary', $documents[0]['title']);
        $this->assertSame('clinician', $documents[0]['source']);
    }

    public function test_the_documents_list_is_scoped_to_the_caller(): void
    {
        $other = User::factory()->role('patient')->create();
        MedicalDocument::create([
            'user_id' => $other->id,
            'title' => 'Someone elses record',
            'category' => 'other',
            'file_type' => 'pdf',
            'uploaded_by' => 'Dr. Someone',
            'uploaded_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);
        $this->getJson('/api/v1/patient/documents')
            ->assertOk()
            ->assertJsonCount(0, 'data.documents');
    }

    public function test_patient_can_open_their_issued_report(): void
    {
        $report = $this->issuedReport();
        Sanctum::actingAs($this->patient);

        $response = $this->get(
            "/api/v1/patient/report-consents/{$report->id}/document"
        );

        $response->assertOk();
        $response->assertHeader('content-type', 'text/html; charset=UTF-8');
        // A medical disclosure must not be left in a shared cache.
        $this->assertStringContainsString('no-store', $response->headers->get('cache-control'));

        $html = $response->getContent();
        $this->assertStringContainsString('Discharge paperwork', $html);
        $this->assertStringContainsString($this->patient->fullName(), $html);
        // Provenance: a disclosure the patient cannot trace is one they
        // cannot challenge.
        $this->assertStringContainsString('About this report', $html);
        $this->assertStringContainsString('Kampala Insurers', $html);
    }

    public function test_an_unissued_report_has_no_document_to_open(): void
    {
        $report = PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'title' => 'Still a draft',
            'purpose' => 'Internal review',
            'sections' => ['identity'],
            'status' => PatientReportRequest::STATUS_PENDING_CONSENT,
        ]);

        Sanctum::actingAs($this->patient);

        $this->getJson("/api/v1/patient/report-consents/{$report->id}/document")
            ->assertNotFound();
    }

    public function test_one_patient_cannot_open_another_patients_report(): void
    {
        $report = $this->issuedReport();
        $intruder = User::factory()->role('patient')->create();

        Sanctum::actingAs($intruder);

        $this->getJson("/api/v1/patient/report-consents/{$report->id}/document")
            ->assertNotFound();
    }

    public function test_a_revoked_report_stays_readable_but_says_so(): void
    {
        $report = $this->issuedReport();
        $report->update([
            'status' => PatientReportRequest::STATUS_REVOKED,
            'revoked_at' => now(),
            'revoke_reason' => 'Sent to the wrong recipient',
        ]);

        Sanctum::actingAs($this->patient);
        $response = $this->get("/api/v1/patient/report-consents/{$report->id}/document");

        $response->assertOk();
        $html = $response->getContent();
        $this->assertStringContainsString('revoked', $html);
        $this->assertStringContainsString('Sent to the wrong recipient', $html);
    }

    public function test_the_consent_list_says_which_reports_can_be_opened(): void
    {
        $issued = $this->issuedReport();
        $draft = PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'title' => 'Not issued',
            'purpose' => 'Internal review',
            'sections' => ['identity'],
            'status' => PatientReportRequest::STATUS_PENDING_CONSENT,
        ]);

        Sanctum::actingAs($this->patient);
        $rows = $this->getJson('/api/v1/patient/report-consents')
            ->assertOk()
            ->json('data.report_requests');

        $byId = collect($rows)->keyBy('id');
        $this->assertTrue($byId[(string) $issued->id]['can_open_document']);
        $this->assertFalse($byId[(string) $draft->id]['can_open_document']);
    }

    /**
     * Report content is escaped on the way out: it carries free text typed by
     * staff and pulled from the record, and it is opened outside the app.
     */
    public function test_report_content_is_escaped(): void
    {
        $report = $this->issuedReport(recipient: '<script>alert(1)</script>');

        Sanctum::actingAs($this->patient);
        $html = $this->get("/api/v1/patient/report-consents/{$report->id}/document")
            ->assertOk()
            ->getContent();

        $this->assertStringNotContainsString('<script>alert(1)</script>', $html);
        $this->assertStringContainsString('&lt;script&gt;', $html);
    }

    private function issuedReport(string $recipient = 'Kampala Insurers'): PatientReportRequest
    {
        $report = PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'title' => 'Discharge paperwork',
            'purpose' => 'Insurance claim',
            'recipient' => $recipient,
            'sections' => ['identity'],
            'status' => PatientReportRequest::STATUS_ISSUED,
            'issued_at' => now(),
        ]);

        // Issue through the service so the stored snapshot is the real frozen
        // assembly, not a hand-built stand-in.
        app(\App\Services\PatientReportService::class)->issue($this->admin, $report);

        return $report->fresh();
    }

    /** Puts the patient on the doctor's caseload so DoctorAccess lets them in. */
    private function attachDoctorToPatient(): void
    {
        $provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => 'Dr. '.$this->doctor->fullName(),
            'specialty' => 'General',
        ]);

        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);
    }
}
