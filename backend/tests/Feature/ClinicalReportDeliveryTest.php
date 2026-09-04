<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\ClinicalReport;
use App\Models\MedicalDocument;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A published clinical report the patient can actually open.
 *
 * Publishing used to mean a boolean on a row and a notification reading "New
 * clinical report", whose action route is `/patient/documents`. Nothing ever
 * put a document there. The patient tapped the alert they were sent, landed on
 * the one screen where their records live, and found an empty list — which
 * reads as an app that lies rather than a report that is late.
 *
 * The chart-note path was worse: it published to the patient and did not even
 * notify them.
 */
class ClinicalReportDeliveryTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;

    private User $doctor;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Storage::fake('local');

        $this->patient = User::factory()->role('patient')->create();
        $this->doctor = User::factory()->role('doctor')->create();
        $this->assignToCaseload();
    }

    public function test_publishing_a_report_files_it_in_the_patient_documents(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/reports', [
            'patient_user_id' => $this->patient->id,
            'title' => 'AMG',
            'body' => "Reviewed today.\nContinue current dose.",
            'publish' => true,
        ])->assertCreated();

        $report = ClinicalReport::firstOrFail();
        $filed = MedicalDocument::where('clinical_report_id', $report->id)->first();

        $this->assertNotNull(
            $filed,
            'Publishing a clinical report must put a copy in the patient documents.',
        );
        $this->assertSame((int) $this->patient->id, (int) $filed->user_id);
        $this->assertSame('report', $filed->category);
        $this->assertSame(MedicalDocument::SOURCE_REPORT, $filed->source);
        // HTML, recorded as such, or it arrives as an unopenable `.bin`.
        $this->assertSame('text/html', $filed->mime_type);
    }

    public function test_the_patient_can_open_it_the_moment_it_is_published(): void
    {
        $report = $this->publishReport('AMG', 'The findings in full.');
        $filed = MedicalDocument::where('clinical_report_id', $report->id)->firstOrFail();

        Sanctum::actingAs($this->patient);

        $listed = $this->getJson('/api/v1/patient/documents');
        $listed->assertOk();
        $this->assertContains(
            (string) $filed->id,
            collect($listed->json('data.documents'))->pluck('id')->all(),
        );

        $streamed = $this->get("/api/v1/patient/documents/{$filed->id}/stream");
        $streamed->assertOk();
        $this->assertStringStartsWith(
            'text/html',
            $streamed->headers->get('Content-Type'),
        );
        // A streamed response writes its body from a callback, so the content
        // has to be drained rather than read off the response object.
        $this->assertStringContainsString(
            'The findings in full.',
            $streamed->streamedContent(),
        );
    }

    public function test_the_notification_points_at_a_document_that_exists(): void
    {
        $report = $this->publishReport('AMG', 'Body.');

        $notification = AppNotification::where('user_id', $this->patient->id)
            ->where('title', 'New clinical report')
            ->first();

        $this->assertNotNull($notification, 'The patient must be told.');
        $this->assertSame('/patient/documents', $notification->action_route);
        // The whole failure was an alert routing to an empty screen.
        $this->assertTrue(
            MedicalDocument::where('clinical_report_id', $report->id)->exists(),
            'The screen the notification points at must have the report on it.',
        );
    }

    public function test_a_draft_reaches_the_patient_nowhere(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/reports', [
            'patient_user_id' => $this->patient->id,
            'title' => 'Work in progress',
            'body' => 'Not finished.',
            'publish' => false,
        ])->assertCreated();

        $this->assertSame(0, MedicalDocument::count(), 'A draft is not a disclosure.');
        $this->assertSame(0, AppNotification::where('user_id', $this->patient->id)->count());
    }

    public function test_publishing_a_draft_later_delivers_it(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/reports', [
            'patient_user_id' => $this->patient->id,
            'title' => 'Follow-up',
            'body' => 'Ready now.',
            'publish' => false,
        ])->assertCreated();

        $report = ClinicalReport::firstOrFail();
        $this->patchJson("/api/v1/doctor/reports/{$report->id}/publish")->assertOk();

        $this->assertTrue(
            MedicalDocument::where('clinical_report_id', $report->id)->exists(),
        );
    }

    public function test_republishing_cannot_file_a_second_copy(): void
    {
        $report = $this->publishReport('AMG', 'Body.');

        Sanctum::actingAs($this->doctor);
        $this->patchJson("/api/v1/doctor/reports/{$report->id}/publish")->assertOk();

        $this->assertSame(
            1,
            MedicalDocument::where('clinical_report_id', $report->id)->count(),
            'A patient holding two copies of one report cannot tell which is current.',
        );
        $this->assertSame(
            1,
            AppNotification::where('user_id', $this->patient->id)
                ->where('title', 'New clinical report')
                ->count(),
            'They were told once; telling them again says something new happened.',
        );
    }

    public function test_correcting_a_published_report_updates_the_copy_the_patient_holds(): void
    {
        $report = $this->publishReport('AMG', 'The dose is 10mg.');
        $filed = MedicalDocument::where('clinical_report_id', $report->id)->firstOrFail();

        Sanctum::actingAs($this->doctor);
        $this->patchJson("/api/v1/doctor/reports/{$report->id}", [
            'body' => 'Correction: the dose is 5mg.',
        ])->assertOk();

        $this->assertSame(
            1,
            MedicalDocument::where('clinical_report_id', $report->id)->count(),
            'A correction replaces the copy rather than filing a rival to it.',
        );

        Sanctum::actingAs($this->patient);
        $streamed = $this->get("/api/v1/patient/documents/{$filed->id}/stream");
        $streamed->assertOk();
        // Reading last week's wording of a report the doctor has since
        // corrected is worse than reading none.
        $content = $streamed->streamedContent();
        $this->assertStringContainsString('the dose is 5mg', $content);
        $this->assertStringNotContainsString('The dose is 10mg', $content);
    }

    public function test_the_patient_cannot_delete_a_published_report(): void
    {
        $report = $this->publishReport('AMG', 'Body.');
        $filed = MedicalDocument::where('clinical_report_id', $report->id)->firstOrFail();

        Sanctum::actingAs($this->patient);

        $this->deleteJson("/api/v1/patient/documents/{$filed->id}")
            ->assertForbidden();

        $this->assertTrue(MedicalDocument::whereKey($filed->id)->exists());
    }

    public function test_a_note_published_from_the_chart_also_reaches_them(): void
    {
        Sanctum::actingAs($this->doctor);

        $this->postJson("/api/v1/doctor/patients/{$this->patient->id}/notes", [
            'title' => 'Ward round',
            'body' => 'Observations recorded at the bedside.',
            'publish' => true,
        ])->assertCreated();

        $report = ClinicalReport::firstOrFail();

        // "Saved and shared" has to mean the patient can read it. This path
        // filed nothing and notified nobody.
        $this->assertTrue(
            MedicalDocument::where('clinical_report_id', $report->id)->exists(),
            'A note published from the chart must reach the patient documents.',
        );
        $this->assertTrue(
            AppNotification::where('user_id', $this->patient->id)
                ->where('title', 'New clinical report')
                ->exists(),
        );
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private function publishReport(string $title, string $body): ClinicalReport
    {
        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/reports', [
            'patient_user_id' => $this->patient->id,
            'title' => $title,
            'body' => $body,
            'publish' => true,
        ])->assertCreated();

        return ClinicalReport::firstOrFail();
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
}
