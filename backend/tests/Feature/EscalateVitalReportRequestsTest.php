<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class EscalateVitalReportRequestsTest extends TestCase
{
    use RefreshDatabase;

    private function makeRequest(User $patient, string $responder, int $ageHours): \App\Models\VitalReportRequest
    {
        $req = $patient->vitalReportRequests()->create([
            'range_from' => now()->subDays(7),
            'range_to' => now(),
            'vitals' => ['heart_rate'],
            'status' => 'pending',
            'current_responder' => $responder,
        ]);
        // Force the anchor timestamp into the past.
        $req->created_at = now()->subHours($ageHours);
        $req->save();

        return $req->fresh();
    }

    public function test_doctor_request_escalates_to_assistant_after_48h(): void
    {
        $patient = User::factory()->create();
        $req = $this->makeRequest($patient, 'doctor', 50);

        $this->artisan('vitals:escalate-report-requests')->assertExitCode(0);

        $this->assertSame('mcareAssistant', $req->fresh()->current_responder);
        $this->assertNotNull($req->fresh()->last_escalated_at);
    }

    public function test_assistant_request_escalates_to_admin_after_24h(): void
    {
        $patient = User::factory()->create();
        $req = $this->makeRequest($patient, 'mcareAssistant', 26);

        $this->artisan('vitals:escalate-report-requests')->assertExitCode(0);

        $this->assertSame('admin', $req->fresh()->current_responder);
    }

    public function test_recent_request_is_not_escalated(): void
    {
        $patient = User::factory()->create();
        $req = $this->makeRequest($patient, 'doctor', 2);

        $this->artisan('vitals:escalate-report-requests')->assertExitCode(0);

        $this->assertSame('doctor', $req->fresh()->current_responder);
    }

    public function test_fulfilled_request_is_left_untouched(): void
    {
        $patient = User::factory()->create();
        $req = $patient->vitalReportRequests()->create([
            'range_from' => now()->subDays(7),
            'range_to' => now(),
            'vitals' => ['heart_rate'],
            'status' => 'fulfilled',
            'current_responder' => 'doctor',
        ]);
        $req->created_at = now()->subHours(100);
        $req->save();

        $this->artisan('vitals:escalate-report-requests')->assertExitCode(0);

        $this->assertSame('doctor', $req->fresh()->current_responder);
    }
}
