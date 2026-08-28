<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\ClinicalReport;
use App\Models\EmergencyContact;
use App\Models\Medication;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalReading;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The clinical chart behind "Open the patient chart".
 *
 * The sheet used to show the account — identity, a score, a list of
 * conditions — so whoever opened it mid-emergency still had to leave it to
 * find the medications, the last readings, the next of kin to call. These pin
 * that the chart carries the record, that a period filter actually filters
 * it, and that a doctor cannot read a chart outside their caseload.
 */
class PatientChartTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $patient;
    private User $doctor;
    private CareProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->admin = User::factory()->role('admin')->create();
        $this->patient = User::factory()->role('patient')->create();
        $this->doctor = User::factory()->role('doctor')->create();

        $this->provider = CareProvider::create([
            'user_id' => $this->doctor->id,
            'name' => 'Dr. '.$this->doctor->fullName(),
            'specialty' => 'Cardiology',
        ]);
    }

    private function url(string $prefix = 'admin', string $query = ''): string
    {
        return "/api/v1/{$prefix}/patients/{$this->patient->id}/chart{$query}";
    }

    private function assign(): void
    {
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);
    }

    private function reading(string $risk, int $daysAgo, float $value = 120): void
    {
        VitalReading::create([
            'user_id' => $this->patient->id,
            'vital_key' => 'heartRate',
            'value' => $value,
            'risk' => $risk,
            'recorded_at' => now()->subDays($daysAgo),
        ]);
    }

    public function test_the_chart_carries_the_record_not_just_the_account(): void
    {
        $this->assign();
        $this->reading('normal', 1);
        $this->reading('critical', 2);

        EmergencyContact::create([
            'user_id' => $this->patient->id,
            'name' => 'Chidi Okonkwo',
            'relationship' => 'Brother',
            'phone' => '+254712000111',
            'priority' => 1,
        ]);
        Medication::create([
            'user_id' => $this->patient->id,
            'name' => 'Amlodipine',
            'dosage' => '5mg',
            'frequency' => 'Daily',
            'start_date' => now()->subDays(3),
            'active' => true,
        ]);
        Appointment::create([
            'user_id' => $this->patient->id,
            'doctor_name' => 'Dr. Adeyemi',
            'scheduled_at' => now()->subDays(2),
            'type' => 'in_person',
            'status' => 'completed',
        ]);
        SosEvent::create([
            'user_id' => $this->patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'location_label' => 'Nairobi, Westlands',
            'latitude' => -1.2649,
            'longitude' => 36.8036,
            'triggered_at' => now()->subDay(),
        ]);

        Sanctum::actingAs($this->admin);
        $data = $this->getJson($this->url())->assertOk()->json('data');

        $this->assertCount(1, $data['next_of_kin'], 'who to call is part of the chart');
        $this->assertCount(1, $data['care_team']);
        $this->assertCount(1, $data['medications']);
        $this->assertCount(1, $data['appointments']);
        $this->assertCount(1, $data['sos']);
        $this->assertSame('Nairobi, Westlands', $data['location']['last_seen_label']);
        $this->assertSame(-1.2649, $data['location']['latitude']);

        $vital = $data['vitals'][0];
        $this->assertSame('heartRate', $vital['key']);
        $this->assertSame(2, $vital['count']);
        $this->assertCount(2, $vital['points'], 'a trend needs its points');
        $this->assertSame(50, $vital['in_range_pct']);
        $this->assertSame(50, $data['summary']['in_range_pct']);
    }

    public function test_the_period_filter_actually_filters(): void
    {
        $this->reading('normal', 2);
        $this->reading('normal', 45);

        Sanctum::actingAs($this->admin);

        $recent = $this->getJson($this->url('admin', '?days=7'))
            ->assertOk()
            ->json('data.summary.readings');
        $this->assertSame(1, $recent);

        $wider = $this->getJson($this->url('admin', '?days=90'))
            ->assertOk()
            ->json('data.summary.readings');
        $this->assertSame(2, $wider);
    }

    public function test_an_explicit_date_range_is_honoured(): void
    {
        $this->reading('normal', 10);
        $this->reading('normal', 40);

        $from = now()->subDays(20)->toDateString();
        $to = now()->toDateString();

        Sanctum::actingAs($this->admin);
        $this->getJson($this->url('admin', "?from={$from}&to={$to}"))
            ->assertOk()
            ->assertJsonPath('data.summary.readings', 1);
    }

    public function test_nothing_measured_is_not_reported_as_healthy(): void
    {
        Sanctum::actingAs($this->admin);

        $this->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.summary.in_range_pct', null);
    }

    public function test_a_doctor_reads_their_own_caseload_only(): void
    {
        Sanctum::actingAs($this->doctor);
        $this->getJson($this->url('doctor'))->assertStatus(403);

        $this->assign();
        $this->getJson($this->url('doctor'))
            ->assertOk()
            ->assertJsonPath('data.patient.id', (string) $this->patient->id);
    }

    public function test_reading_a_chart_is_audited(): void
    {
        Sanctum::actingAs($this->admin);
        $this->getJson($this->url())->assertOk();

        $this->assertDatabaseHas('audit_entries', [
            'actor_user_id' => $this->admin->id,
            'action' => 'patient.chart_viewed',
        ]);
    }

    public function test_a_note_written_from_the_chart_lands_on_it(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/patients/{$this->patient->id}/notes", [
            'title' => 'Chest tightness — responded',
            'body' => 'Patient reached by phone, ambulance dispatched.',
            'publish' => true,
        ])->assertCreated()
            ->assertJsonPath('data.note.published', true);

        $this->assertDatabaseHas('clinical_reports', [
            'patient_user_id' => $this->patient->id,
            'author_user_id' => $this->admin->id,
            'title' => 'Chest tightness — responded',
        ]);

        $notes = $this->getJson($this->url())->assertOk()->json('data.notes');
        $this->assertCount(1, $notes, 'the note is on the chart it was written from');
        $this->assertSame($this->admin->fullName(), $notes[0]['author_name']);
    }

    public function test_an_older_note_is_outside_a_short_window(): void
    {
        $note = ClinicalReport::create([
            'patient_user_id' => $this->patient->id,
            'author_user_id' => $this->doctor->id,
            'title' => 'Old note',
            'body' => 'From before the window.',
            'published' => true,
            'published_at' => now()->subDays(60),
        ]);
        $note->forceFill(['created_at' => now()->subDays(60)])->save();

        Sanctum::actingAs($this->admin);

        $this->getJson($this->url('admin', '?days=7'))
            ->assertOk()
            ->assertJsonPath('data.summary.notes', 0);

        $this->getJson($this->url('admin', '?days=90'))
            ->assertOk()
            ->assertJsonPath('data.summary.notes', 1);
    }
}
