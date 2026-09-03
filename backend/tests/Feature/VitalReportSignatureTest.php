<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
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
 * A vital report is a clinical document the patient is handed, so it has to
 * carry a signature — who attested to the findings, in what capacity, and
 * when — not merely an author line saying who typed the note.
 *
 * The signature is recorded on the request and rendered into the filed file,
 * so the copy in the app and a copy printed on paper say the same thing.
 */
class VitalReportSignatureTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;
    private User $doctor;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Storage::fake('local');

        $admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();
        $this->doctor = User::factory()->role('doctor')->create();

        $provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => 'Dr. '.$this->doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $admin->id,
        ]);

        VitalReading::create([
            'user_id' => $this->patient->id,
            'vital_key' => 'heartRate',
            'value' => 72,
            'risk' => 'normal',
            'recorded_at' => now()->subDays(3),
        ]);
    }

    private function openRequest(): VitalReportRequest
    {
        Sanctum::actingAs($this->patient);

        return VitalReportRequest::findOrFail(
            $this->postJson('/api/v1/patient/vital-report-requests', [
                'range_from' => now()->subDays(14)->toDateString(),
                'range_to' => now()->toDateString(),
                'vitals' => ['heartRate'],
            ])->assertCreated()->json('data.request.id')
        );
    }

    private function fulfil(VitalReportRequest $request): void
    {
        Sanctum::actingAs($this->doctor);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/claim")
            ->assertOk();
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/fulfill", [
            'note' => 'Rate is settled; keep logging mornings.',
        ])->assertOk();
    }

    public function test_an_open_request_carries_no_signature(): void
    {
        $request = $this->openRequest();

        $this->assertNull($request->signed_at);
        $this->assertNull($request->signed_by);

        Sanctum::actingAs($this->patient);
        $this->getJson('/api/v1/patient/vital-report-requests')
            ->assertOk()
            ->assertJsonPath('data.requests.0.signed_at', null)
            ->assertJsonPath('data.requests.0.signed_by', null);
    }

    public function test_fulfilling_signs_the_request(): void
    {
        $request = $this->openRequest();
        $this->fulfil($request);

        $request->refresh();

        $this->assertNotNull($request->signed_at);
        $this->assertSame($this->doctor->id, $request->signed_by_user_id);
        $this->assertSame('Dr. '.$this->doctor->fullName(), $request->signed_by);
        $this->assertSame('doctor', $request->signed_by_role);

        // Signed and resolved are the same moment: the report is issued *by*
        // the act of signing, not filed first and attested afterwards.
        $this->assertEquals(
            $request->signed_at->timestamp,
            $request->resolved_at->timestamp,
        );
    }

    public function test_the_patient_is_told_who_signed_and_when(): void
    {
        $request = $this->openRequest();
        $this->fulfil($request);

        Sanctum::actingAs($this->patient);
        $row = $this->getJson('/api/v1/patient/vital-report-requests')
            ->assertOk()
            ->json('data.requests.0');

        $this->assertSame('Dr. '.$this->doctor->fullName(), $row['signed_by']);
        $this->assertSame('doctor', $row['signed_by_role']);
        $this->assertNotNull($row['signed_at']);
    }

    public function test_the_filed_document_carries_the_signature_block(): void
    {
        $request = $this->openRequest();
        $this->fulfil($request);

        $request->refresh();
        $document = MedicalDocument::findOrFail($request->document_id);
        $html = Storage::disk('local')->get($document->storage_path);

        $this->assertStringContainsString('Signed off', $html);
        $this->assertStringContainsString('Attending clinician', $html);
        $this->assertStringContainsString(
            'Dr. '.$this->doctor->fullName(),
            $html,
        );
        $this->assertStringContainsString(
            $request->signed_at->format('j M Y'),
            $html,
        );
    }

    public function test_a_second_fulfil_cannot_overwrite_the_signature(): void
    {
        $request = $this->openRequest();
        $this->fulfil($request);

        $request->refresh();
        $firstSignedAt = $request->signed_at;
        $firstSigner = $request->signed_by_user_id;

        // The request is closed, so a repeat is refused rather than re-signed.
        Sanctum::actingAs($this->doctor);
        $this->patchJson("/api/v1/doctor/vital-report-requests/{$request->id}/fulfill")
            ->assertStatus(422);

        $request->refresh();
        $this->assertSame($firstSigner, $request->signed_by_user_id);
        $this->assertEquals(
            $firstSignedAt->timestamp,
            $request->signed_at->timestamp,
        );
    }
}
