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

    /**
     * An unsigned report is readable — the admin who raised it is allowed to
     * check what they asked for. A closed one is not, because there is nothing
     * to decide and nothing was ever issued.
     */
    public function test_a_closed_request_has_no_report_to_open(): void
    {
        $report = $this->readyToIssue();
        $report->update([
            'status' => PatientReportRequest::STATUS_REVOKED,
            'revoked_at' => now(),
        ]);

        Sanctum::actingAs($this->admin);
        $this->getJson("/api/v1/admin/report-requests/{$report->id}/document")
            ->assertNotFound();

        $this->getJson("/api/v1/admin/report-requests/{$report->id}")
            ->assertOk()
            ->assertJsonMissingPath('data.document');
    }

    public function test_an_unsigned_report_can_still_be_read_as_a_draft(): void
    {
        $report = $this->readyToIssue();
        $report->update([
            'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE,
            'signed_at' => null,
            'signature_name' => null,
        ]);

        Sanctum::actingAs($this->admin);
        $html = $this->get("/api/v1/admin/report-requests/{$report->id}/document")
            ->assertOk()
            ->getContent();

        // Says both things that are missing, not just one of them.
        $this->assertStringContainsString('DRAFT', $html);
        $this->assertStringContainsString('or signed', $html);
    }

    // ---------------------------------------------------------------
    // Raising a report: no patient consent, a nominated doctor
    // ---------------------------------------------------------------

    public function test_raising_a_report_goes_straight_to_the_doctor(): void
    {
        $this->attachDoctor();
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/report-requests", [
            'sections' => ['identity', 'health_profile'],
            'title' => 'Referral letter',
            'purpose' => 'Specialist referral',
            'doctor_user_id' => $this->doctor->id,
        ])->assertCreated();

        $report = PatientReportRequest::where('patient_user_id', $this->patient->id)
            ->firstOrFail();

        $this->assertSame(PatientReportRequest::STATUS_PENDING_SIGNATURE, $report->status);
        $this->assertFalse((bool) $report->consent_required);
        $this->assertTrue((bool) $report->signature_required);
        $this->assertNull($report->consent_code_hash, 'A consent challenge was still minted.');

        // Nobody asked the patient for anything.
        $this->assertDatabaseMissing('app_notifications', [
            'user_id' => $this->patient->id,
            'title' => 'Approve sharing of your record',
        ]);

        // The nominated doctor was told.
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $this->doctor->id,
            'title' => 'Report awaiting your signature',
        ]);
    }

    /**
     * Even a report of nothing but a name and patient id needs a signature.
     * Deriving the gate from the ticked sections meant an administrative-only
     * report could be issued with nobody having read it.
     */
    public function test_even_an_administrative_report_needs_a_signature(): void
    {
        $this->attachDoctor();
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/report-requests", [
            'sections' => ['identity'],
            'title' => 'Proof of registration',
            'purpose' => 'Employer letter',
            'doctor_user_id' => $this->doctor->id,
        ])->assertCreated();

        $report = PatientReportRequest::where('patient_user_id', $this->patient->id)
            ->firstOrFail();

        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")
            ->assertStatus(422);
    }

    public function test_a_report_cannot_be_raised_without_naming_a_doctor(): void
    {
        $this->attachDoctor();
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/report-requests", [
            'sections' => ['identity'],
            'title' => 'Referral letter',
            'purpose' => 'Specialist referral',
        ])->assertStatus(422)->assertJsonValidationErrors('doctor_user_id');
    }

    /**
     * Nominating a signer must not become a way to hand a whole record to a
     * clinician who has no relationship with the patient — the caseload gate
     * everywhere else exists to stop exactly that.
     */
    public function test_a_doctor_off_the_care_team_cannot_be_nominated(): void
    {
        $stranger = User::factory()->role('doctor')->create();
        $this->attachDoctor();
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/report-requests", [
            'sections' => ['identity'],
            'title' => 'Referral letter',
            'purpose' => 'Specialist referral',
            'doctor_user_id' => $stranger->id,
        ])->assertStatus(422);

        $this->assertDatabaseCount('patient_report_requests', 0);
    }

    public function test_the_signer_list_is_the_patients_care_team_doctors(): void
    {
        $this->attachDoctor();
        Sanctum::actingAs($this->admin);

        $this->getJson("/api/v1/admin/patients/{$this->patient->id}/report-signers")
            ->assertOk()
            ->assertJsonPath('data.signers.0.user_id', (string) $this->doctor->id)
            ->assertJsonPath('data.signers.0.is_primary', true)
            ->assertJsonCount(1, 'data.signers');
    }

    public function test_a_patient_with_no_care_team_offers_no_signer(): void
    {
        Sanctum::actingAs($this->admin);

        $this->getJson("/api/v1/admin/patients/{$this->patient->id}/report-signers")
            ->assertOk()
            ->assertJsonCount(0, 'data.signers');
    }

    // ---------------------------------------------------------------
    // The admin's decision on a signed report
    // ---------------------------------------------------------------

    public function test_a_signed_report_can_be_parked_under_review(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/under-review", [
            'note' => 'Checking the discharge date with the ward.',
        ])->assertOk();

        $report->refresh();
        $this->assertSame(PatientReportRequest::STATUS_UNDER_REVIEW, $report->status);
        $this->assertNotNull($report->under_review_at);
        $this->assertSame('Checking the discharge date with the ward.', $report->under_review_note);

        // Parking is an annotation, not a new gate — it stays issuable.
        $this->assertNotNull($report->signed_at);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();
    }

    public function test_an_unsigned_report_cannot_be_parked(): void
    {
        $report = $this->readyToIssue();
        $report->update(['signed_at' => null, 'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE]);

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/under-review")
            ->assertStatus(422);
    }

    public function test_rejecting_deletes_the_request(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->deleteJson("/api/v1/admin/report-requests/{$report->id}", [
            'reason' => 'Prepared for the wrong patient.',
        ])->assertOk();

        $this->assertDatabaseMissing('patient_report_requests', ['id' => $report->id]);

        // Nothing was disclosed, so nothing reached the patient's documents.
        $this->assertDatabaseMissing('medical_documents', [
            'user_id' => $this->patient->id,
        ]);
    }

    /**
     * The row goes; what it was does not. Deleting is only defensible because
     * the audit entry outlives it.
     */
    public function test_a_rejection_leaves_the_whole_request_in_the_audit_trail(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->deleteJson("/api/v1/admin/report-requests/{$report->id}", [
            'reason' => 'Prepared for the wrong patient.',
        ])->assertOk();

        $entry = \App\Models\AuditEntry::where('action', 'report.rejected')->first();

        $this->assertNotNull($entry, 'A deleted report request left no trace.');
        $meta = json_encode($entry->meta);
        $this->assertStringContainsString('Prepared for the wrong patient.', $meta);
        $this->assertStringContainsString('Discharge paperwork', $meta);
        $this->assertStringContainsString('Dr. Signer', $meta);
    }

    public function test_the_doctor_is_told_their_signed_report_was_rejected(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->deleteJson("/api/v1/admin/report-requests/{$report->id}", [
            'reason' => 'Prepared for the wrong patient.',
        ])->assertOk();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $this->doctor->id,
            'title' => 'Signed report rejected',
        ]);
    }

    /**
     * Once a copy is in the patient's documents, "delete" is not an operation
     * anyone can perform on what already happened.
     */
    public function test_an_issued_report_cannot_be_rejected(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        $this->deleteJson("/api/v1/admin/report-requests/{$report->id}", [
            'reason' => 'Changed my mind.',
        ])->assertStatus(422);

        $this->assertDatabaseHas('patient_report_requests', ['id' => $report->id]);
    }

    public function test_an_unissued_report_cannot_be_revoked(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/revoke", [
            'reason' => 'Nothing went out.',
        ])->assertStatus(422);

        $this->assertDatabaseHas('patient_report_requests', ['id' => $report->id]);
    }

    // ---------------------------------------------------------------
    // The retired consent surface
    // ---------------------------------------------------------------

    public function test_the_patient_consent_endpoints_are_gone(): void
    {
        $report = $this->readyToIssue();
        Sanctum::actingAs($this->patient);

        $this->postJson("/api/v1/patient/report-consents/{$report->id}/approve")
            ->assertNotFound();
        $this->postJson("/api/v1/patient/report-consents/{$report->id}/decline")
            ->assertNotFound();
    }

    /**
     * The patient keeps the half that was worth keeping: seeing what was sent
     * about them, and reading it.
     */
    public function test_the_patient_still_sees_reports_drawn_from_their_record(): void
    {
        $report = $this->readyToIssue();
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/issue")->assertOk();

        Sanctum::actingAs($this->patient);
        $this->getJson('/api/v1/patient/report-consents')
            ->assertOk()
            ->assertJsonPath('data.report_requests.0.title', 'Discharge paperwork')
            // Nothing is ever waiting on them now.
            ->assertJsonPath('data.report_requests.0.awaiting_me', false);

        $this->get("/api/v1/patient/report-consents/{$report->id}/document")
            ->assertOk();
    }

    // ---------------------------------------------------------------
    // Sending a signed report back to the doctor
    // ---------------------------------------------------------------

    public function test_sending_back_clears_the_signature_but_keeps_the_request(): void
    {
        $report = $this->readyToIssue();

        Sanctum::actingAs($this->admin);
        $this->postJson("/api/v1/admin/report-requests/{$report->id}/send-back", [
            'note' => 'Recipient address is wrong.',
        ])->assertOk();

        $report->refresh();

        $this->assertNull($report->signed_at, 'The signature survived the return trip.');
        // The request itself survives untouched — same sections, same doctor,
        // same recipient. Only the signature, which was given against content
        // about to change, is cleared.
        $this->assertSame(['identity'], $report->sections);
        $this->assertSame((int) $this->doctor->id, (int) $report->doctor_user_id);
        $this->assertSame('Kampala Insurers', $report->recipient);
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
            'consent_required' => false,
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
