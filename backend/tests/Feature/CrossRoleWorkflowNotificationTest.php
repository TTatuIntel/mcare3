<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AssistantPermission;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\Conversation;
use App\Models\SupportTicket;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CrossRoleWorkflowNotificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_patient_message_reaches_doctor_session_and_shared_inbox_state(): void
    {
        $patient = User::factory()->role('patient')->create();
        $doctor = User::factory()->role('doctor')->create();
        $conversation = Conversation::create([
            'user_id' => $patient->id,
            'participant_user_id' => $doctor->id,
            'participant_name' => $doctor->fullName(),
            'participant_role' => 'doctor',
        ]);

        Sanctum::actingAs($patient);
        $this->postJson("/api/v1/patient/conversations/{$conversation->id}/messages", [
            'body' => 'Please review my latest readings.',
        ])->assertCreated();

        $notification = AppNotification::query()
            ->where('user_id', $doctor->id)
            ->where('kind', 'message')
            ->sole();
        $this->assertSame((string) $conversation->id, $notification->action_arguments['conversation_id']);

        Sanctum::actingAs($doctor);
        $this->getJson('/api/v1/doctor/session')
            ->assertOk()
            ->assertJsonFragment([
                'id' => (string) $notification->id,
                'kind' => 'message',
            ]);

        $this->patchJson("/api/v1/me/notifications/{$notification->id}/read")
            ->assertOk()
            ->assertJsonPath('data.notification.read', true);
        $this->assertDatabaseHas('app_notifications', [
            'id' => $notification->id,
            'read' => true,
        ]);
    }

    public function test_reading_a_patient_thread_clears_its_durable_message_notice(): void
    {
        $patient = User::factory()->role('patient')->create();
        $doctor = User::factory()->role('doctor')->create();
        $provider = CareProvider::create([
            'user_id' => $doctor->id,
            'name' => $doctor->fullName(),
            'specialty' => 'General medicine',
        ]);
        CareAssignment::create([
            'patient_user_id' => $patient->id,
            'provider_id' => $provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
        ]);
        $conversation = Conversation::create([
            'user_id' => $patient->id,
            'participant_user_id' => $doctor->id,
            'participant_name' => $doctor->fullName(),
            'participant_role' => 'doctor',
        ]);

        Sanctum::actingAs($doctor);
        $this->postJson("/api/v1/doctor/conversations/{$conversation->id}/messages", [
            'body' => 'I reviewed them. Please continue tracking.',
        ])->assertCreated();

        $notification = AppNotification::query()
            ->where('user_id', $patient->id)
            ->where('kind', 'message')
            ->sole();
        $this->assertFalse($notification->read);

        Sanctum::actingAs($patient);
        $this->postJson("/api/v1/patient/conversations/{$conversation->id}/read")
            ->assertOk();

        $this->assertTrue($notification->fresh()->read);
    }

    public function test_care_and_support_workflows_notify_the_right_people(): void
    {
        $patient = User::factory()->role('patient')->create();
        $admin = User::factory()->role('admin')->create();
        $assistant = User::factory()->role('mcare_assistant')->create();
        AssistantPermission::create([
            'user_id' => $assistant->id,
            'permission_key' => 'can_manage_care_requests',
            'granted_by_user_id' => $admin->id,
        ]);
        $provider = CareProvider::create([
            'user_id' => User::factory()->role('doctor')->create()->id,
            'name' => 'Dr. Care Provider',
            'specialty' => 'Family medicine',
        ]);

        Sanctum::actingAs($patient);
        $this->postJson('/api/v1/patient/care/requests', [
            'provider_id' => $provider->id,
            'reason' => 'Ongoing care',
        ])->assertCreated();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $admin->id,
            'kind' => 'care_request',
        ]);
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $assistant->id,
            'kind' => 'care_request',
        ]);

        $ticketId = $this->postJson('/api/v1/patient/support-tickets', [
            'subject' => 'Cannot update my profile',
            'description' => 'The save action needs support.',
            'category' => 'technical',
            'priority' => 'high',
        ])->assertCreated()->json('data.ticket.id');

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $admin->id,
            'kind' => 'support',
        ]);
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $assistant->id,
            'kind' => 'support',
        ]);

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/admin/session')
            ->assertOk()
            ->assertJsonFragment(['kind' => 'care_request'])
            ->assertJsonFragment(['kind' => 'support']);

        $ticket = SupportTicket::findOrFail($ticketId);
        $this->postJson("/api/v1/admin/support-tickets/{$ticket->id}/replies", [
            'body' => 'We are reviewing this now.',
        ])->assertOk();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'support',
            'title' => 'Support replied',
        ]);
    }

    public function test_appointment_writes_notify_the_other_participant(): void
    {
        $patient = User::factory()->role('patient')->create();
        $doctor = User::factory()->role('doctor')->create();
        $scheduledAt = now()->addDays(2)->seconds(0);

        Sanctum::actingAs($patient);
        $appointmentId = $this->postJson('/api/v1/patient/appointments', [
            'doctor_name' => 'Dr. '.$doctor->fullName(),
            'doctor_user_id' => $doctor->id,
            'doctor_specialty' => 'General medicine',
            'scheduled_at' => $scheduledAt->toIso8601String(),
            'type' => 'virtual',
        ])->assertCreated()->json('data.appointment.id');

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $doctor->id,
            'kind' => 'appointment',
            'title' => 'New appointment request',
        ]);

        Sanctum::actingAs($doctor);
        $this->patchJson("/api/v1/doctor/appointments/{$appointmentId}", [
            'status' => 'confirmed',
        ])->assertOk();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'appointment',
            'title' => 'Appointment updated',
        ]);
    }
}
