<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppNotification;
use App\Models\ExternalAccessToken;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §4.2 refactor safety net.
 *
 * Locks in the exact top-level keys + item shape returned by the three
 * controllers being converted to JsonResource. If a refactor accidentally
 * renames a field or changes wrapping, this test fires — before Flutter
 * ever sees the broken response.
 *
 * We assert *keys*, not values, because timestamps / IDs vary per run.
 */
class ResponseShapeParityTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_notifications_index_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'vital_warning',
            'title' => 'Elevated HR',
            'body' => 'Heart rate at 125.',
            'action_route' => '/patient/vitals',
            'action_arguments' => ['vital_key' => 'heart_rate'],
            'read' => false,
            'resolved' => false,
        ]);

        Sanctum::actingAs($patient);

        $response = $this->getJson('/api/v1/patient/notifications')->assertOk();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'notifications' => [
                    ['id', 'kind', 'title', 'body', 'action_route', 'action_arguments',
                     'read', 'resolved', 'resolved_at', 'created_at'],
                ],
            ],
            'message',
        ]);

        // Field types matter to Flutter — id is stringified, read/resolved are booleans.
        $first = $response->json('data.notifications.0');
        $this->assertIsString($first['id']);
        $this->assertIsBool($first['read']);
        $this->assertIsBool($first['resolved']);
    }

    public function test_notification_mark_read_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        $notif = AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'message',
            'title' => 'Hi',
            'body' => 'Test',
            'read' => false,
            'resolved' => false,
        ]);

        Sanctum::actingAs($patient);

        $response = $this->patchJson("/api/v1/patient/notifications/{$notif->id}/read")
            ->assertOk();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'notification' => [
                    'id', 'kind', 'title', 'body', 'action_route', 'action_arguments',
                    'read', 'resolved', 'resolved_at', 'created_at',
                ],
            ],
            'message',
        ]);
        $this->assertTrue($response->json('data.notification.read'));
    }

    public function test_vitals_index_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        VitalReading::create([
            'user_id' => $patient->id,
            'vital_key' => 'heart_rate',
            'value' => 72,
            'risk' => 'normal',
            'recorded_at' => now(),
        ]);

        Sanctum::actingAs($patient);

        $response = $this->getJson('/api/v1/patient/vitals')->assertOk();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'vitals' => [
                    ['id', 'vital', 'vital_key', 'value', 'secondary_value',
                     'display_value', 'risk', 'recorded_at', 'note'],
                ],
            ],
            'message',
        ]);

        // Flutter's parser reads `vital` and `vital_key` (backwards compat) and
        // relies on `display_value` for formatting — all three must remain present.
        $first = $response->json('data.vitals.0');
        $this->assertSame('heart_rate', $first['vital']);
        $this->assertSame('heart_rate', $first['vital_key']);
        $this->assertIsString($first['display_value']);
    }

    public function test_vital_store_shape(): void
    {
        VitalCatalog::create([
            'vital_key' => 'heart_rate',
            'normal_min' => 60, 'normal_max' => 100,
            'warning_low' => 50, 'warning_high' => 120,
            'critical_low' => 40, 'critical_high' => 150,
            'enabled' => true,
        ]);

        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/vitals', [
            'vital_key' => 'heart_rate',
            'value' => 75,
        ])->assertCreated();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'vital' => [
                    'id', 'vital', 'vital_key', 'value', 'secondary_value',
                    'display_value', 'risk', 'recorded_at', 'note',
                ],
            ],
            'message',
        ]);
    }

    public function test_external_access_index_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        ExternalAccessToken::create([
            'patient_user_id' => $patient->id,
            'created_by_user_id' => $patient->id,
            'token' => str_repeat('a', 64),
            'access_code' => 'ABCD-1234',
            'label' => 'ER',
            'expires_at' => now()->addDay(),
        ]);

        Sanctum::actingAs($patient);

        $response = $this->getJson('/api/v1/patient/external-access')->assertOk();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'links' => [
                    ['id', 'label', 'access_code', 'url', 'token', 'expires_at',
                     'revoked_at', 'active', 'created_at'],
                ],
            ],
            'message',
        ]);
        $first = $response->json('data.links.0');
        $this->assertIsString($first['id']);
        $this->assertIsBool($first['active']);
    }

    public function test_external_access_store_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/external-access', [
            'label' => 'Test',
        ])->assertCreated();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'link' => ['id', 'label', 'access_code', 'url', 'token',
                    'expires_at', 'revoked_at', 'active', 'created_at'],
            ],
            'message',
        ]);
    }

    public function test_medication_store_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/medications', [
            'name' => 'Amoxicillin',
            'dosage' => '500 mg',
            'frequency' => 'Twice daily',
            'start_date' => now()->toDateString(),
        ])->assertCreated();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'medication' => ['id', 'name', 'dosage', 'frequency', 'form',
                    'instructions', 'prescribed_by', 'start_date', 'end_date',
                    'expiry_date', 'refills_left', 'source', 'active'],
            ],
            'message',
        ]);
        $this->assertIsBool($response->json('data.medication.active'));
    }

    public function test_appointment_store_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/appointments', [
            'doctor_name' => 'Dr. Test',
            'scheduled_at' => now()->addDay()->toIso8601String(),
            'type' => 'inPerson',
        ])->assertCreated();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'appointment' => ['id', 'doctor_id', 'doctor_name',
                    'doctor_specialty', 'scheduled_at', 'duration_minutes',
                    'type', 'status', 'reason', 'location_or_link',
                    'cancellation_reason'],
            ],
            'message',
        ]);
    }

    public function test_sos_trigger_shape(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $response = $this->postJson('/api/v1/patient/sos', [
            'kind' => 'medical',
        ])->assertCreated();

        $response->assertJsonStructure([
            'success',
            'data' => [
                'event' => ['id', 'kind', 'status', 'location_label',
                    'latitude', 'longitude', 'note', 'responded_by',
                    'triggered_at', 'responded_at'],
            ],
            'message',
        ]);
    }
}
