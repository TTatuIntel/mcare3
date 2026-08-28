<?php

namespace Tests\Feature;

use App\Events\RealtimeDataChanged;
use App\Events\VitalAlertBroadcast;
use App\Models\AppNotification;
use App\Models\MealPlan;
use App\Models\PatientReportRequest;
use App\Models\SosResponseAction;
use App\Models\User;
use App\Models\UserSetting;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DemoDatasetTest extends TestCase
{
    use RefreshDatabase;

    public function test_one_seed_builds_complete_roles_and_runtime_simulation_uses_real_events(): void
    {
        Storage::fake('public');
        config([
            'broadcasting.default' => 'reverb',
            'broadcasting.connections.reverb' => [
                'driver' => 'reverb',
                'key' => 'test-key',
                'secret' => 'test-secret',
                'app_id' => 'test-app',
            ],
        ]);
        Event::fake([RealtimeDataChanged::class, VitalAlertBroadcast::class]);

        $this->seed();

        $this->artisan('mcare:demo-status', ['--strict' => true, '--json' => true])
            ->assertSuccessful();
        $this->assertSame(5, User::where('role', 'patient')->count());
        $this->assertSame(User::count(), UserSetting::count());
        $this->assertSame(5, MealPlan::distinct()->count('patient_user_id'));
        $this->assertSame(5, PatientReportRequest::count());
        $this->assertGreaterThan(0, SosResponseAction::count());
        $this->assertSame(0, DB::table('jobs')->count());
        Event::assertNotDispatched(RealtimeDataChanged::class);

        $patient = User::where('email', 'amara.okonkwo@example.com')->firstOrFail();
        Sanctum::actingAs($patient);
        $patientSession = $this->getJson('/api/v1/patient/session')->assertOk();
        $this->assertNotEmpty($patientSession->json('data.vitals'));
        $this->assertNotEmpty($patientSession->json('data.medications'));
        $this->assertNotEmpty($patientSession->json('data.appointments'));
        $this->assertNotEmpty($patientSession->json('data.documents'));
        $this->assertNotEmpty($patientSession->json('data.conversations'));

        $doctor = User::where('email', 'dr.mensah@mcare.health')->firstOrFail();
        Sanctum::actingAs($doctor);
        $doctorSession = $this->getJson('/api/v1/doctor/session')->assertOk();
        $this->assertNotEmpty($doctorSession->json('data.caseload'));
        $this->assertNotEmpty($doctorSession->json('data.appointments'));

        foreach (['admin@mcare.health', 'assistant@mcare.health'] as $email) {
            Sanctum::actingAs(User::where('email', $email)->firstOrFail());
            $staffSession = $this->getJson('/api/v1/admin/session')->assertOk();
            $this->assertNotEmpty($staffSession->json('data.users'));
            $this->assertNotEmpty($staffSession->json('data.sos_events'));
        }

        $this->artisan('mcare:simulate', [
            'scenario' => 'vital-critical',
            '--patient' => 'brian.otieno@example.com',
            '--json' => true,
        ])->assertSuccessful();

        $brian = User::where('email', 'brian.otieno@example.com')->firstOrFail();
        $this->assertDatabaseHas('vital_readings', [
            'user_id' => $brian->id,
            'vital_key' => 'bloodOxygen',
            'risk' => 'critical',
        ]);
        $this->assertTrue(AppNotification::query()
            ->where('user_id', $brian->id)
            ->where('kind', 'vital_critical')
            ->where('resolved', false)
            ->exists());
        Event::assertDispatched(RealtimeDataChanged::class);
        Event::assertDispatched(VitalAlertBroadcast::class);
    }
}
