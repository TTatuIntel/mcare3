<?php

namespace Tests\Feature;

use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MealPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * A meal plan is a timetable entry, not a standing note: it belongs to a day,
 * a patient may add their own, and the record of whether it was followed is
 * what the care team reads back.
 */
class MealPlanTimetableTest extends TestCase
{
    use RefreshDatabase;

    private User $patient;
    private User $doctor;
    private User $admin;
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
            'specialty' => 'Endocrinology',
        ]);

        CareAssignment::create([
            'patient_user_id' => $this->patient->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);
    }

    public function test_a_doctor_can_assign_one_meal_across_several_days(): void
    {
        Sanctum::actingAs($this->doctor);

        $days = [
            now()->toDateString(),
            now()->addDay()->toDateString(),
            now()->addDays(2)->toDateString(),
        ];

        $this->postJson('/api/v1/doctor/meal-plans', [
            'patient_user_id' => $this->patient->id,
            'title' => 'Low-sodium breakfast',
            'meal_type' => 'breakfast',
            'scheduled_for' => $days,
            'serve_time' => '07:30',
            'condition_tag' => 'Hypertension',
            'items' => ['Oats', 'Berries'],
        ])->assertCreated()
            ->assertJsonCount(3, 'data.meal_plans');

        $this->assertSame(3, MealPlan::count());
        $this->assertSame(
            $days,
            MealPlan::orderBy('scheduled_for')
                ->pluck('scheduled_for')
                ->map(fn ($d) => $d->toDateString())
                ->all(),
        );
        $this->assertSame('Hypertension', MealPlan::first()->condition_tag);
        $this->assertSame(['Oats', 'Berries'], MealPlan::first()->items);
    }

    public function test_one_assign_can_cover_several_patients(): void
    {
        $second = User::factory()->role('patient')->create();
        CareAssignment::create([
            'patient_user_id' => $second->id,
            'provider_id' => $this->provider->id,
            'role' => 'Primary',
            'assigned_at' => now(),
            'assigned_by' => $this->admin->id,
        ]);

        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/meal-plans', [
            'patient_user_ids' => [$this->patient->id, $second->id],
            'title' => 'Renal-friendly dinner',
            'meal_type' => 'dinner',
        ])->assertCreated()
            ->assertJsonCount(2, 'data.meal_plans');

        $this->assertSame(1, MealPlan::where('patient_user_id', $this->patient->id)->count());
        $this->assertSame(1, MealPlan::where('patient_user_id', $second->id)->count());
    }

    public function test_a_patient_off_the_caseload_is_refused_for_the_whole_batch(): void
    {
        $stranger = User::factory()->role('patient')->create();
        Sanctum::actingAs($this->doctor);

        $this->postJson('/api/v1/doctor/meal-plans', [
            'patient_user_ids' => [$this->patient->id, $stranger->id],
            'title' => 'Should not be written',
            'meal_type' => 'lunch',
        ])->assertForbidden();

        $this->assertSame(0, MealPlan::count());
    }

    public function test_a_patient_can_add_and_remove_their_own_meal(): void
    {
        Sanctum::actingAs($this->patient);

        $response = $this->postJson('/api/v1/patient/meal-plans', [
            'title' => 'Roasted groundnuts',
            'meal_type' => 'snack',
            'scheduled_for' => now()->addDay()->toDateString(),
            'serve_time' => '16:00',
            'items' => ['Handful of groundnuts'],
        ])->assertCreated()
            ->assertJsonPath('data.meal_plan.source', 'patient')
            ->assertJsonPath('data.meal_plan.assigned_by', 'You');

        $id = $response->json('data.meal_plan.id');

        $this->deleteJson("/api/v1/patient/meal-plans/{$id}")->assertOk();
        $this->assertSame(0, MealPlan::count());
    }

    public function test_a_patient_cannot_edit_or_delete_a_clinicians_plan(): void
    {
        $plan = MealPlan::create([
            'patient_user_id' => $this->patient->id,
            'assigned_by_user_id' => $this->doctor->id,
            'source' => MealPlan::SOURCE_CARE_TEAM,
            'title' => 'Low-sodium lunch',
            'meal_type' => 'lunch',
            'assigned_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);

        $this->patchJson("/api/v1/patient/meal-plans/{$plan->id}", [
            'title' => 'Chips',
        ])->assertForbidden();

        $this->deleteJson("/api/v1/patient/meal-plans/{$plan->id}")
            ->assertForbidden();

        $this->assertSame('Low-sodium lunch', $plan->fresh()->title);
    }

    public function test_a_patient_can_log_progress_on_a_clinicians_plan(): void
    {
        $plan = MealPlan::create([
            'patient_user_id' => $this->patient->id,
            'assigned_by_user_id' => $this->doctor->id,
            'source' => MealPlan::SOURCE_CARE_TEAM,
            'title' => 'Low-sodium lunch',
            'meal_type' => 'lunch',
            'assigned_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);

        $this->postJson("/api/v1/patient/meal-plans/{$plan->id}/log", [
            'adherence' => 'partial',
            'patient_note' => 'Ate about half.',
        ])->assertOk()
            ->assertJsonPath('data.meal_plan.adherence', 'partial');

        $plan->refresh();
        $this->assertSame('partial', $plan->adherence);
        $this->assertSame('Ate about half.', $plan->patient_note);
        $this->assertNotNull($plan->logged_at);

        // Clearing the log takes the timestamp away with it.
        $this->postJson("/api/v1/patient/meal-plans/{$plan->id}/log", [
            'adherence' => 'pending',
        ])->assertOk();

        $this->assertNull($plan->fresh()->logged_at);
    }

    public function test_a_patient_cannot_log_against_someone_elses_plan(): void
    {
        $other = User::factory()->role('patient')->create();
        $plan = MealPlan::create([
            'patient_user_id' => $other->id,
            'source' => MealPlan::SOURCE_CARE_TEAM,
            'title' => 'Not yours',
            'meal_type' => 'dinner',
            'assigned_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);

        $this->postJson("/api/v1/patient/meal-plans/{$plan->id}/log", [
            'adherence' => 'followed',
        ])->assertNotFound();
    }

    public function test_the_session_payload_carries_the_timetable_fields(): void
    {
        MealPlan::create([
            'patient_user_id' => $this->patient->id,
            'assigned_by_user_id' => $this->doctor->id,
            'source' => MealPlan::SOURCE_CARE_TEAM,
            'title' => 'Low-sodium breakfast',
            'meal_type' => 'breakfast',
            'scheduled_for' => now()->addDay()->toDateString(),
            'serve_time' => '07:30',
            'condition_tag' => 'Hypertension',
            'items' => ['Oats'],
            'assigned_at' => now(),
        ]);

        Sanctum::actingAs($this->patient);

        $this->getJson('/api/v1/patient/session')
            ->assertOk()
            ->assertJsonPath('data.meal_plans.0.serve_time', '07:30')
            ->assertJsonPath('data.meal_plans.0.condition_tag', 'Hypertension')
            ->assertJsonPath('data.meal_plans.0.adherence', 'pending')
            ->assertJsonPath(
                'data.meal_plans.0.scheduled_for',
                now()->addDay()->toDateString(),
            );
    }

    public function test_a_plan_written_before_scheduling_falls_back_to_its_assign_date(): void
    {
        $plan = MealPlan::create([
            'patient_user_id' => $this->patient->id,
            'source' => MealPlan::SOURCE_CARE_TEAM,
            'title' => 'Legacy plan',
            'meal_type' => 'general',
            'assigned_at' => now()->subDays(3),
        ]);
        $plan->forceFill(['scheduled_for' => null])->save();

        $this->assertSame(
            now()->subDays(3)->toDateString(),
            $plan->fresh()->toApiArray()['scheduled_for'],
        );
    }
}
