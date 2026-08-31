<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class NewUserAdminNotificationTest extends TestCase
{
    use RefreshDatabase;

    public function test_patient_registration_notifies_each_active_admin_once(): void
    {
        Mail::fake();
        $admin = User::factory()->create([
            'role' => 'admin',
            'approval_status' => 'active',
        ]);
        $suspended = User::factory()->create([
            'role' => 'admin',
            'approval_status' => 'suspended',
        ]);

        $response = $this->postJson('/api/v1/auth/register', [
            'first_name' => 'Kibs',
            'last_name' => 'Patient',
            'email' => 'kibs@example.com',
            'phone' => '+256700000001',
            'password' => 'secure-password',
        ])->assertCreated();

        $patientId = $response->json('data.user.id');
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $admin->id,
            'kind' => 'new_user',
            'title' => 'New Patient joined',
            'read' => false,
        ]);
        $this->assertDatabaseMissing('app_notifications', [
            'user_id' => $suspended->id,
            'kind' => 'new_user',
        ]);
        $this->assertDatabaseMissing('app_notifications', [
            'user_id' => $patientId,
            'kind' => 'new_user',
        ]);
    }
}
