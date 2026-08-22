<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\VitalCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §5.3 / §13 — vital-alert → notification server-side generation.
 *
 * A threshold breach must write an `app_notifications` row (server-side).
 * A normal reading must NOT write one. This test locks in that the client
 * never has to compute notification content.
 */
class VitalAlertToNotificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        VitalCatalog::create([
            'vital_key' => 'heart_rate',
            'normal_min' => 60,
            'normal_max' => 100,
            'warning_low' => 50,
            'warning_high' => 120,
            'critical_low' => 40,
            'critical_high' => 150,
            'enabled' => true,
        ]);
    }

    public function test_critical_reading_creates_notification(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 180, // above critical_high (150)
        ])->assertCreated();

        $this->assertDatabaseHas('vital_readings', [
            'user_id' => $patient->id,
            'vital_key' => 'heart_rate',
            'risk' => 'critical',
        ]);

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'vital_critical',
        ]);
    }

    public function test_warning_reading_creates_notification(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 130, // between warning_high (120) and critical_high (150)
        ])->assertCreated();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'vital_warning',
        ]);
    }

    public function test_normal_reading_does_not_create_notification(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 75,
        ])->assertCreated();

        $this->assertDatabaseHas('vital_readings', [
            'user_id' => $patient->id,
            'risk' => 'normal',
        ]);
        $this->assertDatabaseMissing('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'vital_critical',
        ]);
        $this->assertDatabaseMissing('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'vital_warning',
        ]);
    }

    public function test_duplicate_alerts_within_thirty_minutes_are_suppressed(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        // Two identical critical readings back-to-back should produce one alert.
        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 180,
        ])->assertCreated();

        $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 185,
        ])->assertCreated();

        $this->assertSame(
            1,
            \App\Models\AppNotification::where('user_id', $patient->id)
                ->where('kind', 'vital_critical')
                ->count(),
        );
    }
}
