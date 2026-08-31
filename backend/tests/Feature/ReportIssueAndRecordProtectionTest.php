<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MedicalDocument;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Models\VitalCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * What happens after a doctor signs, and what may never be undone.
 *
 * Issuing used to end in mid-air: the report was frozen, the patient was told
 * it had gone out, and then nothing. Staff had no file to hand the recipient
 * they had prepared it for, and the patient had a line on a consent screen
 * rather than a copy anywhere they would look for one. Issuing now files that
 * copy into the patient's own documents, which makes "the admin approved it"
 * and "the patient has it" the same event.
 *
 * The other half is what cannot happen. Nothing in a patient's record should
 * vanish on one person's say-so — a wrong document is superseded, a report
 * that should not have gone out is revoked, and both leave a trace where
 * deletion leaves none.
 */
class ReportIssueAndRecordProtectionTest extends TestCase
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

    // ---------------------------------------------------------------
    // Issuing delivers
    // ---------------------------------------------------------------

    public function test_issuing_files_a_copy_into_the_patients_documents(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")
            ->assertOk();

        $filed = MedicalDocument::where('user_id', $this->patient->id)->first();

        $this->assertNotNull($filed, 'Issuing left the patient with no copy.');
        $this->assertSame('Discharge paperwork', $filed->title);
        $this->assertSame(MedicalDocument::SOURCE_REPORT, $filed->source);
        $this->assertSame((int) $report->id, (int) $filed->issued_report_id);
        // The copy is a real file, not just a row.
        $this->assertTrue($filed->size_bytes > 0);
        Storage::disk('local')->assertExists($filed->storage_path);
    }

    public function test_the_filed_copy_is_the_frozen_report(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $filed = MedicalDocument::where('user_id', $this->patient->id)->firstOrFail();
        $html = Storage::disk('local')->get($filed->storage_path);

        $this->assertStringContainsString('Discharge paperwork', $html);
        $this->assertStringContainsString($this->patient->fullName(), $html);
        $this->assertStringContainsString('Kampala Insurers', $html);
    }

    public function test_the_patient_is_told_the_copy_arrived(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $this->patient->id,
            'kind' => 'document',
        ]);

        $consentNote = AppNotification::where('user_id', $this->patient->id)
            ->where('kind', 'consent')
            ->first();
        $this->assertNotNull($consentNote);
        $this->assertStringContainsString('copy is in your documents', $consentNote->body);
    }

    public function test_admin_can_download_the_issued_report(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $response = $this->get("/api/v1/admin/report-requests/{$report->id}/document");

        $response->assertOk();
        $response->assertHeader('content-type', 'text/html; charset=UTF-8');
        $this->assertStringContainsString('Discharge paperwork', $response->getContent());
    }

    /**
     * The admin reviewing a signed report can read it, and what they read
     * cannot be mistaken for the finished thing.
     *
     * Refusing this outright was the wrong answer to a real risk: it left the
     * admin approving a document they had never seen. The risk is that a draft
     * looks identical to an issued report once it is saved to disk, so the
     * draft says so on its face instead.
     */
    public function test_a_signed_report_can_be_read_before_issue_but_is_marked_draft(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $html = $this->get("/api/v1/admin/report-requests/{$report->id}/document")
            ->assertOk()
            ->getContent();

        $this->assertStringContainsString('DRAFT', $html);
        $this->assertStringContainsString('must not be sent', $html);
        $this->assertStringContainsString('Discharge paperwork', $html);
    }

    public function test_the_draft_preview_is_refused_until_the_patient_consents(): void
    {
        $report = PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'doctor_user_id' => $this->doctor->id,
            'title' => 'Discharge paperwork',
            'purpose' => 'Insurance claim',
            'sections' => ['identity'],
            'status' => PatientReportRequest::STATUS_PENDING_CONSENT,
            'consent_required' => true,
            'signature_required' => true,
        ]);

        Sanctum::actingAs($this->admin);
        $this->getJson("/api/v1/admin/report-requests/{$report->id}/document")
            ->assertNotFound();

        $this->getJson("/api/v1/admin/report-requests/{$report->id}")
            ->assertOk()
            ->assertJsonMissingPath('data.document');
    }

    // ---------------------------------------------------------------
    // Sending a signed report back to the doctor
    // ---------------------------------------------------------------

    public function test_sending_back_clears_the_signature_but_keeps_the_consent(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Recipient address is wrong.',
        ])->assertOk();

        $report->refresh();

        $this->assertNull($report->signed_at, 'The signature survived the return trip.');
        $this->assertNotNull(
            $report->consented_at,
            'Sending back threw away consent the patient had already given.',
        );
        $this->assertSame(PatientReportRequest::STATUS_PENDING_SIGNATURE, $report->status);
        $this->assertSame('Recipient address is wrong.', $report->return_note);
        $this->assertSame(1, (int) $report->return_count);
    }

    public function test_a_returned_report_cannot_be_issued(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Needs the discharge date.',
        ])->assertOk();

        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")
            ->assertStatus(422);

        $this->assertDatabaseMissing('medical_documents', [
            'user_id' => $this->patient->id,
            'source' => MedicalDocument::SOURCE_REPORT,
        ]);
    }

    public function test_the_doctor_is_told_what_to_change(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Add the medication review.',
        ])->assertOk();

        $note = AppNotification::where('user_id', $this->doctor->id)
            ->where('title', 'Report sent back for changes')
            ->first();

        $this->assertNotNull($note, 'The doctor was never told the report came back.');
        $this->assertStringContainsString('Add the medication review.', $note->body);
    }

    public function test_re_signing_clears_the_return_but_keeps_the_count(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Wrong recipient.',
        ])->assertOk();

        Sanctum::actingAs($this->doctor);
        $this->postJson("/api/v1/doctor/report-requests/{$report->id}/sign", [
            'signature_name' => 'Dr. Signer',
        ])->assertOk();

        $report->refresh();

        $this->assertNull($report->returned_at);
        $this->assertNull($report->return_note);
        $this->assertNotNull($report->signed_at);
        $this->assertSame(
            1,
            (int) $report->return_count,
            'The history of how many times this report came back was erased.',
        );
    }

    public function test_an_issued_report_cannot_be_sent_back(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Too late.',
        ])->assertStatus(422);
    }

    public function test_a_revoked_report_warns_staff_not_to_forward_it(): void
    {
        $report = $this->readyToIssue();
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $this->postJson("/api/v1/admin/report-requests/{$report->id}/revoke", [
            'reason' => 'Sent to the wrong recipient',
        ])->assertOk();

        $html = $this->get("/api/v1/admin/report-requests/{$report->id}/document")
            ->assertOk()
            ->getContent();

        $this->assertStringContainsString('revoked', $html);
        $this->assertStringContainsString('must not be relied on', $html);
    }

    // ---------------------------------------------------------------
    // The record is protected
    // ---------------------------------------------------------------

    public function test_a_patient_cannot_delete_an_issued_report(): void
    {
        $report = $this->readyToIssue();
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $filed = MedicalDocument::where('user_id', $this->patient->id)->firstOrFail();

        Sanctum::actingAs($this->patient);
        $this->deleteJson("/api/v1/patient/documents/{$filed->id}")
            ->assertForbidden();

        $this->assertDatabaseHas('medical_documents', ['id' => $filed->id]);
    }

    public function test_a_patient_cannot_delete_what_a_clinician_filed(): void
    {
        $document = MedicalDocument::create([
            'user_id' => $this->patient->id,
            'title' => 'Discharge summary',
            'category' => 'discharge',
            'file_type' => 'pdf',
            'uploaded_by' => 'Dr. Someone',
            'uploaded_at' => now(),
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        Sanctum::actingAs($this->patient);
        $this->deleteJson("/api/v1/patient/documents/{$document->id}")
            ->assertForbidden();

        $this->assertDatabaseHas('medical_documents', ['id' => $document->id]);
    }

    public function test_a_patient_can_still_delete_their_own_upload(): void
    {
        Sanctum::actingAs($this->patient);

        $id = $this->postJson('/api/v1/patient/documents', [
            'title' => 'Photo of my pill bottle',
            'category' => 'other',
            'file_type' => 'image',
            'file' => UploadedFile::fake()->create('bottle.jpg', 10, 'image/jpeg'),
        ])->assertCreated()->json('data.document.id');

        $this->deleteJson("/api/v1/patient/documents/{$id}")->assertOk();
        $this->assertDatabaseMissing('medical_documents', ['id' => $id]);
    }

    /** Legacy rows predate provenance and were all patient uploads. */
    public function test_a_document_with_no_recorded_source_stays_deletable(): void
    {
        $document = MedicalDocument::create([
            'user_id' => $this->patient->id,
            'title' => 'Old upload',
            'category' => 'other',
            'file_type' => 'pdf',
            'uploaded_by' => 'Someone',
            'uploaded_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);
        $this->deleteJson("/api/v1/patient/documents/{$document->id}")->assertOk();
    }

    public function test_a_doctor_can_no_longer_delete_from_the_record(): void
    {
        $this->attachDoctor();
        $document = MedicalDocument::create([
            'user_id' => $this->patient->id,
            'title' => 'Lab panel',
            'category' => 'labResult',
            'file_type' => 'pdf',
            'uploaded_by' => 'Dr. Someone',
            'uploaded_at' => now(),
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        Sanctum::actingAs($this->doctor);
        $this->deleteJson(
            "/api/v1/doctor/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertForbidden();

        $this->assertDatabaseHas('medical_documents', ['id' => $document->id]);
    }

    public function test_admin_cannot_delete_on_their_own_initiative(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->admin);
        $this->deleteJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertForbidden();

        $this->assertDatabaseHas('medical_documents', ['id' => $document->id]);
    }

    // ---------------------------------------------------------------
    // The one authorised way out: the patient asks
    // ---------------------------------------------------------------

    public function test_a_patient_can_ask_for_a_clinician_document_to_be_removed(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'This belongs to another patient.',
        ])->assertOk();

        $document->refresh();
        $this->assertNotNull($document->removal_requested_at);
        $this->assertSame('This belongs to another patient.', $document->removal_reason);
    }

    public function test_a_standing_request_is_what_lets_staff_delete(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'Filed against the wrong person.',
        ])->assertOk();

        Sanctum::actingAs($this->admin);
        $this->deleteJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertOk();

        $this->assertDatabaseMissing('medical_documents', ['id' => $document->id]);
    }

    /**
     * The row goes; the fact that it existed does not. Removing a document is
     * the only deletion in the record, and it is worthless as an audit trail
     * if it leaves nothing behind saying what was removed and why.
     */
    public function test_honouring_a_removal_leaves_the_reason_in_the_audit_trail(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'Wrong patient entirely.',
        ])->assertOk();

        Sanctum::actingAs($this->admin);
        $this->deleteJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertOk();

        $entry = \App\Models\AuditEntry::where('action', 'patient.document_removed')->first();

        $this->assertNotNull($entry, 'A deleted document left no trace at all.');
        $this->assertSame('Blood panel', $entry->target);
        $this->assertStringContainsString('Wrong patient entirely.', json_encode($entry->meta));
    }

    public function test_a_doctor_may_honour_a_request_but_not_delete_without_one(): void
    {
        $document = $this->clinicianDocument();
        $this->attachDoctor();

        Sanctum::actingAs($this->doctor);
        $this->deleteJson(
            "/api/v1/doctor/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertForbidden();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'Not my result.',
        ])->assertOk();

        Sanctum::actingAs($this->doctor);
        $this->deleteJson(
            "/api/v1/doctor/patients/{$this->patient->id}/documents/{$document->id}"
        )->assertOk();

        $this->assertDatabaseMissing('medical_documents', ['id' => $document->id]);
    }

    public function test_an_issued_report_cannot_be_removed_even_on_request(): void
    {
        $report = $this->readyToIssue();
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $filed = MedicalDocument::where('issued_report_id', $report->id)->firstOrFail();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$filed->id}/request-removal", [
            'reason' => 'I changed my mind.',
        ])->assertStatus(422);

        Sanctum::actingAs($this->admin);
        $this->deleteJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$filed->id}"
        )->assertForbidden();

        $this->assertDatabaseHas('medical_documents', ['id' => $filed->id]);
    }

    public function test_declining_keeps_the_document_and_tells_the_patient_why(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'I do not want it there.',
        ])->assertOk();

        Sanctum::actingAs($this->admin);
        $this->postJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}/decline-removal",
            ['reason' => 'This result is yours and is clinically relevant.'],
        )->assertOk();

        $document->refresh();
        $this->assertDatabaseHas('medical_documents', ['id' => $document->id]);
        $this->assertNull($document->removal_requested_at, 'The request stayed in the queue.');
        $this->assertNotNull($document->removal_declined_at);

        $note = AppNotification::where('user_id', $this->patient->id)
            ->where('title', 'Removal request declined')
            ->first();
        $this->assertNotNull($note);
        $this->assertStringContainsString('clinically relevant', $note->body);
    }

    /**
     * A refusal answers one request; it does not silence the patient. Asking
     * again clears the refusal so a stale no cannot mask a live request.
     */
    public function test_a_patient_can_ask_again_after_a_refusal(): void
    {
        $document = $this->clinicianDocument();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'Not mine.',
        ])->assertOk();

        Sanctum::actingAs($this->admin);
        $this->postJson(
            "/api/v1/admin/patients/{$this->patient->id}/documents/{$document->id}/decline-removal",
            ['reason' => 'It matches your record.'],
        )->assertOk();

        Sanctum::actingAs($this->patient);
        $this->postJson("/api/v1/patient/documents/{$document->id}/request-removal", [
            'reason' => 'The date of birth on it is not mine.',
        ])->assertOk();

        $document->refresh();
        $this->assertNotNull($document->removal_requested_at);
        $this->assertNull($document->removal_declined_at);
    }

    private function clinicianDocument(): MedicalDocument
    {
        return MedicalDocument::create([
            'user_id' => $this->patient->id,
            'title' => 'Blood panel',
            'category' => 'labResult',
            'file_type' => 'pdf',
            'uploaded_by' => 'Dr. Filed',
            'uploaded_at' => now(),
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);
    }

    // ---------------------------------------------------------------
    // Staff-assisted vitals
    // ---------------------------------------------------------------

    public function test_admin_can_log_a_vital_for_a_patient(): void
    {
        $this->seedHeartRateRange();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/vitals", [
            'vital_key' => 'heartRate',
            'value' => 72,
            'note' => 'Taken at the desk',
        ])->assertCreated();

        $reading = $this->patient->vitalReadings()->first();
        $this->assertNotNull($reading);
        $this->assertSame('normal', $reading->risk);
        // Who typed it is part of the reading: a desk entry and a patient's own
        // measurement carry different confidence.
        $this->assertSame($this->admin->id, $reading->recorded_by_user_id);
        $this->assertStringContainsString('mCare admin', $reading->recorded_by_label);
    }

    public function test_a_staff_logged_reading_alerts_like_the_patients_own(): void
    {
        $this->seedHeartRateRange();

        $this->attachDoctor();
        Sanctum::actingAs($this->doctor);

        $this->postJson("/api/v1/doctor/patients/{$this->patient->id}/vitals", [
            'vital_key' => 'heartRate',
            'value' => 190,
        ])->assertCreated();

        $reading = $this->patient->vitalReadings()->first();
        $this->assertNotSame('normal', $reading->risk);
        $this->assertStringContainsString('Dr.', $reading->recorded_by_label);
    }

    public function test_a_patients_own_reading_records_no_staff_author(): void
    {
        $this->seedHeartRateRange();

        Sanctum::actingAs($this->patient);
        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heartRate',
            'value' => 70,
        ])->assertCreated();

        $reading = $this->patient->vitalReadings()->first();
        $this->assertNull($reading->recorded_by_user_id);
        $this->assertNull($reading->recorded_by_label);
    }

    // ---------------------------------------------------------------

    /** A normal band of 60–100 bpm, so 72 grades normal and 190 does not. */
    private function seedHeartRateRange(): void
    {
        VitalCatalog::create([
            'vital_key' => 'heartRate',
            'normal_min' => 60,
            'normal_max' => 100,
            'warning_low' => 50,
            'warning_high' => 120,
            'critical_low' => 40,
            'critical_high' => 150,
            'enabled' => true,
        ]);
    }

    /** A report the patient consented to and a doctor signed — ready to issue. */
    private function readyToIssue(): PatientReportRequest
    {
        return PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'doctor_user_id' => $this->doctor->id,
            'title' => 'Discharge paperwork',
            'purpose' => 'Insurance claim',
            'recipient' => 'Kampala Insurers',
            'sections' => ['identity'],
            'status' => PatientReportRequest::STATUS_SIGNED,
            'consent_required' => true,
            'consented_at' => now(),
            'consent_method' => 'code',
            'signature_required' => true,
            'signed_at' => now(),
            'signature_name' => 'Dr. Signer',
        ]);
    }

    private function attachDoctor(): void
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
