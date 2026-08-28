<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MessagingDerivedStateTest extends TestCase
{
    use RefreshDatabase;

    public function test_unread_count_is_derived_and_legacy_summary_columns_are_not_written(): void
    {
        [$patient, $doctor, $conversation] = $this->assignedConversation();
        $legacyTimestamp = now()->subDay()->startOfSecond();
        $conversation->forceFill([
            'unread_count' => 91,
            'last_message_at' => $legacyTimestamp,
        ])->saveQuietly();

        Sanctum::actingAs($patient);
        $this->postJson("/api/v1/patient/conversations/{$conversation->id}/messages", [
            'body' => 'Please review my readings.',
        ])->assertCreated()
            ->assertJsonPath('data.message.read', false);

        $message = ChatMessage::where('conversation_id', $conversation->id)->sole();
        $this->assertFalse($message->read);
        $this->assertSame(91, $conversation->fresh()->unread_count);
        $this->assertTrue($conversation->fresh()->last_message_at->equalTo($legacyTimestamp));

        Sanctum::actingAs($doctor);
        $this->getJson('/api/v1/doctor/conversations')
            ->assertOk()
            ->assertJsonPath('data.conversations.0.unread_count', 1)
            ->assertJsonPath('data.conversations.0.last_message.body', 'Please review my readings.');
    }

    public function test_a_doctor_cannot_open_another_doctors_thread_even_on_a_shared_caseload(): void
    {
        [$patient, $doctor, $conversation] = $this->assignedConversation();
        $otherDoctor = User::factory()->role('doctor')->create();
        $otherProvider = CareProvider::resolveForUser($otherDoctor->id);
        CareAssignment::create([
            'patient_user_id' => $patient->id,
            'provider_id' => $otherProvider->id,
            'role' => 'doctor',
            'assigned_at' => now(),
        ]);

        Sanctum::actingAs($otherDoctor);
        $this->getJson("/api/v1/doctor/conversations/{$conversation->id}/messages")
            ->assertForbidden();

        Sanctum::actingAs($doctor);
        $this->getJson("/api/v1/doctor/conversations/{$conversation->id}/messages")
            ->assertOk();
    }

    public function test_admin_oversight_is_read_only_for_threads_the_admin_does_not_join(): void
    {
        [, , $conversation] = $this->assignedConversation();
        $admin = User::factory()->role('admin')->create();
        Sanctum::actingAs($admin);

        $this->getJson("/api/v1/admin/conversations/{$conversation->id}/messages")
            ->assertOk();
        $this->postJson("/api/v1/admin/conversations/{$conversation->id}/messages", [
            'body' => 'This should not be injected into a private thread.',
        ])->assertForbidden();
    }

    /** @return array{User, User, Conversation} */
    private function assignedConversation(): array
    {
        $patient = User::factory()->role('patient')->create();
        $doctor = User::factory()->role('doctor')->create();
        $provider = CareProvider::resolveForUser($doctor->id);
        CareAssignment::create([
            'patient_user_id' => $patient->id,
            'provider_id' => $provider->id,
            'role' => 'doctor',
            'assigned_at' => now(),
        ]);

        $conversation = Conversation::create([
            'user_id' => $patient->id,
            'participant_user_id' => $doctor->id,
            'participant_name' => $doctor->fullName(),
            'participant_role' => 'doctor',
            'participant_specialty' => 'General practice',
        ]);

        return [$patient, $doctor, $conversation];
    }
}
