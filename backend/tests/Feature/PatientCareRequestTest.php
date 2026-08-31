<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * One open request per provider.
 *
 * A patient tapping "Request care" twice — impatience, a double tap, a retry
 * on a flaky connection — must not put two rows on the admin queue for the
 * same doctor. The app hides the button once a request is open; these tests
 * pin the server rule underneath it, which is the one that actually holds.
 */
class PatientCareRequestTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;
    private CareProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);

        $this->patient = User::factory()->role('patient')->create();
        $this->provider = CareProvider::create([
            'user_id' => User::factory()->role('doctor')->create()->id,
            'name' => 'Dr. Kojo Mensah',
            'specialty' => 'Internal medicine',
        ]);

        Sanctum::actingAs($this->patient);
    }

    private function request(?string $reason = null)
    {
        return $this->postJson('/api/v1/patient/care/requests', [
            'provider_id' => $this->provider->id,
            'reason' => $reason,
        ]);
    }

    public function test_first_request_is_created(): void
    {
        $this->request('Chronic disease management')
            ->assertStatus(201)
            ->assertJsonPath('data.request.status', 'pending');

        $this->assertDatabaseCount('care_requests', 1);
    }

    public function test_second_request_for_the_same_provider_returns_the_existing_one(): void
    {
        $first = $this->request('Chronic disease management');
        $firstId = $first->json('data.request.id');

        $second = $this->request('Asking again');

        $second->assertOk()
            ->assertJsonPath('data.request.id', $firstId)
            ->assertJsonPath('data.request.status', 'pending');

        // No second row, and the original reason is untouched.
        $this->assertDatabaseCount('care_requests', 1);
        $this->assertSame(
            'Chronic disease management',
            CareRequest::first()->reason,
        );
    }

    public function test_a_provider_already_on_the_team_cannot_be_requested(): void
    {
        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
        ]);

        $this->request()
            ->assertStatus(422)
            ->assertJsonPath('message', 'Dr. Kojo Mensah is already on your care team.');

        $this->assertDatabaseCount('care_requests', 0);
    }

    public function test_a_new_request_is_allowed_once_the_previous_one_closes(): void
    {
        $first = $this->request();
        $id = $first->json('data.request.id');

        $this->patchJson("/api/v1/patient/care/requests/{$id}")->assertOk();

        // Cancelled is not open, so the patient may ask again.
        $this->request()->assertStatus(201);
        $this->assertDatabaseCount('care_requests', 2);
        $this->assertSame(
            1,
            CareRequest::where('status', 'pending')->count(),
        );
    }

    public function test_another_patient_is_unaffected_by_this_ones_request(): void
    {
        $this->request();

        $other = User::factory()->role('patient')->create();
        Sanctum::actingAs($other);

        $this->request()->assertStatus(201);
        $this->assertDatabaseCount('care_requests', 2);
    }
}
