<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MedicalDocument;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Services\PatientReportService;
use App\Support\MedicalDocumentFiles;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A document you can actually open, and only one copy of it.
 *
 * Everything a document *is* was being re-derived at read time from `file_type`
 * — a four-value enum shared with the Flutter app: pdf, image, doc, other. That
 * is enough to pick an icon and nothing like enough to hand a file to a browser
 * or a share sheet. An issued report is HTML the server renders itself, so it
 * lands in `other`, so it was served as `application/octet-stream` named
 * `.bin`: the one document a patient is explicitly told to go and read was the
 * one nothing on their phone would open.
 *
 * The other half is duplication. Filing the patient's copy of a report checked
 * for an existing row and then wrote one — a read-then-write with a gap in the
 * middle — so a retry after a partial failure could leave a patient holding two
 * copies of one disclosure with no way to tell which was real.
 */
class DocumentFileFidelityTest extends TestCase
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

    // ------------------------------------------------------------------
    // What a stored file is
    // ------------------------------------------------------------------

    public function test_an_upload_records_the_real_type_and_filename(): void
    {
        Sanctum::actingAs($this->patient);

        $response = $this->postJson('/api/v1/patient/documents', [
            'title' => 'March blood panel',
            'category' => 'labResult',
            'file_type' => 'pdf',
            'file' => UploadedFile::fake()->create(
                'MRI-2026-03-11.pdf',
                12,
                'application/pdf',
            ),
        ]);

        $response->assertCreated();
        $response->assertJsonPath('data.document.mime_type', 'application/pdf');
        // The name they saved it under, not a slug of what they typed in the
        // title box — that is what they will look for in their downloads.
        $response->assertJsonPath('data.document.download_name', 'MRI-2026-03-11.pdf');

        $this->assertDatabaseHas('medical_documents', [
            'user_id' => $this->patient->id,
            'mime_type' => 'application/pdf',
            'original_filename' => 'MRI-2026-03-11.pdf',
        ]);
    }

    public function test_the_file_types_a_hospital_actually_produces_are_accepted(): void
    {
        Sanctum::actingAs($this->patient);

        // A scan off a hospital MFP and a home-monitor export. Both were
        // refused by the old `pdf,jpg,jpeg,png,doc,docx` list, which is the set
        // a web form imagines rather than the set a patient is handed.
        foreach ([['scan.tiff', 'image/tiff'], ['readings.csv', 'text/csv']] as [$name, $mime]) {
            $response = $this->postJson('/api/v1/patient/documents', [
                'title' => 'Brought from the clinic',
                'category' => 'imaging',
                'file_type' => 'other',
                'file' => UploadedFile::fake()->create($name, 8, $mime),
            ]);

            $response->assertCreated(
                "Upload of $name was refused; a patient cannot file their own record.",
            );
        }
    }

    public function test_download_asks_for_the_file_and_view_asks_for_the_page(): void
    {
        Sanctum::actingAs($this->patient);

        $document = $this->uploadOwnDocument();

        // View: rendered where the reader is.
        $this->get("/api/v1/patient/documents/{$document->id}/stream")
            ->assertOk()
            ->assertHeader('Content-Type', 'application/pdf')
            ->assertHeaderMissing('Content-Disposition; attachment');

        $inline = $this->get("/api/v1/patient/documents/{$document->id}/stream");
        $this->assertStringStartsWith(
            'inline;',
            $inline->headers->get('Content-Disposition'),
        );

        // Download: onto the reader's device. Both used to be `inline`, so
        // Download opened a tab and produced no file at all.
        $attachment = $this->get("/api/v1/patient/documents/{$document->id}/stream?download=1");
        $attachment->assertOk();
        $this->assertStringStartsWith(
            'attachment;',
            $attachment->headers->get('Content-Disposition'),
        );
        $this->assertStringContainsString(
            'results.pdf',
            $attachment->headers->get('Content-Disposition'),
        );
    }

    public function test_a_legacy_row_without_a_recorded_type_still_opens(): void
    {
        Sanctum::actingAs($this->patient);

        $document = $this->uploadOwnDocument();
        // As every row written before the column existed looks.
        $document->forceFill(['mime_type' => null, 'original_filename' => null])->save();

        $this->get("/api/v1/patient/documents/{$document->id}/stream")
            ->assertOk()
            ->assertHeader('Content-Type', 'application/pdf');

        $this->assertSame(
            'march-blood-panel.pdf',
            $document->fresh()->downloadName(),
            'A row with nothing recorded must still name a file something openable.',
        );
    }

    // ------------------------------------------------------------------
    // Reports reaching the patient
    // ------------------------------------------------------------------

    public function test_an_issued_report_is_filed_as_an_openable_document(): void
    {
        $request = $this->issuedReport();

        $filed = MedicalDocument::where('issued_report_id', $request->id)->first();

        $this->assertNotNull($filed, 'Issuing a report must put a copy in the patient documents.');
        $this->assertSame(MedicalDocument::SOURCE_REPORT, $filed->source);
        // HTML, and recorded as such. Filed with no type it was served as
        // octet-stream named `.bin`.
        $this->assertSame('text/html', $filed->mime_type);
        $this->assertStringEndsWith('.html', $filed->downloadName());
        // Its own category, so it appears under Reports where the patient goes
        // looking rather than buried in "other" among their insurance scans.
        $this->assertSame('report', $filed->category);
    }

    public function test_the_patient_can_open_the_report_the_moment_it_is_issued(): void
    {
        $request = $this->issuedReport();
        $filed = MedicalDocument::where('issued_report_id', $request->id)->firstOrFail();

        Sanctum::actingAs($this->patient);

        $listed = $this->getJson('/api/v1/patient/documents');
        $listed->assertOk();
        $this->assertContains(
            (string) $filed->id,
            collect($listed->json('data.documents'))->pluck('id')->all(),
            'A report the care team just issued must be in the patient list without a full session sync.',
        );

        $streamed = $this->get("/api/v1/patient/documents/{$filed->id}/stream");
        $streamed->assertOk();
        $this->assertStringStartsWith(
            'text/html',
            $streamed->headers->get('Content-Type'),
        );
    }

    public function test_a_report_cannot_be_filed_twice(): void
    {
        $request = $this->issuedReport();

        // What a retry after a partial failure looks like: the same report
        // filed again by a second call that got past the existence check.
        $this->expectException(\Illuminate\Database\UniqueConstraintViolationException::class);

        MedicalDocument::create([
            'user_id' => $this->patient->id,
            'title' => 'Duplicate copy',
            'category' => 'report',
            'file_type' => 'other',
            'mime_type' => 'text/html',
            'storage_path' => 'documents/x/dup.html',
            'size_bytes' => 10,
            'uploaded_by' => 'mCare',
            'uploaded_at' => now(),
            'source' => MedicalDocument::SOURCE_REPORT,
            'issued_report_id' => $request->id,
        ]);
    }

    public function test_re_running_the_issue_leaves_one_copy(): void
    {
        $request = $this->issuedReport();

        app(PatientReportService::class)->issue($this->admin, $request->fresh());

        $this->assertSame(
            1,
            MedicalDocument::where('issued_report_id', $request->id)->count(),
            'A patient holding two copies of one disclosure cannot tell which is real.',
        );
    }

    // ------------------------------------------------------------------
    // The care team reading the same record
    // ------------------------------------------------------------------

    public function test_a_doctor_can_list_the_documents_of_a_patient_on_their_caseload(): void
    {
        Sanctum::actingAs($this->patient);
        $document = $this->uploadOwnDocument();

        $this->assignToCaseload();
        Sanctum::actingAs($this->doctor);

        $response = $this->getJson(
            "/api/v1/doctor/patients/{$this->patient->id}/documents",
        );

        $response->assertOk();
        $response->assertJsonPath('data.documents.0.id', (string) $document->id);
        // The care team reads the same truth about the file the patient does,
        // or it hands clinicians the same unopenable `.bin`.
        $response->assertJsonPath('data.documents.0.mime_type', 'application/pdf');
    }

    public function test_a_doctor_cannot_list_the_documents_of_a_stranger(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->getJson("/api/v1/doctor/patients/{$this->patient->id}/documents")
            ->assertForbidden();
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private function uploadOwnDocument(): MedicalDocument
    {
        $this->postJson('/api/v1/patient/documents', [
            'title' => 'March blood panel',
            'category' => 'labResult',
            'file_type' => 'pdf',
            'file' => UploadedFile::fake()->create('results.pdf', 12, 'application/pdf'),
        ])->assertCreated();

        return MedicalDocument::where('user_id', $this->patient->id)
            ->latest('id')
            ->firstOrFail();
    }

    private function assignToCaseload(): void
    {
        $provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => $this->doctor->fullName(),
            'specialty' => 'General',
        ]);

        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
        ]);
    }

    /** A report taken all the way through signature to issue. */
    private function issuedReport(): PatientReportRequest
    {
        $request = PatientReportRequest::create([
            'patient_user_id' => $this->patient->id,
            'requested_by_user_id' => $this->admin->id,
            'doctor_user_id' => $this->doctor->id,
            'title' => 'Continuity of care summary',
            'purpose' => 'Referral to a specialist',
            'recipient' => 'Demo receiving facility',
            'sections' => ['profile'],
            'consent_required' => false,
            'signature_required' => true,
            'status' => PatientReportRequest::STATUS_SIGNED,
            'signed_at' => now(),
            'signature_name' => 'Dr. '.$this->doctor->fullName(),
        ]);

        app(PatientReportService::class)->issue($this->admin, $request);

        return $request->fresh();
    }
}
