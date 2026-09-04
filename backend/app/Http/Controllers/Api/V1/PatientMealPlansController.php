<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MealPlan;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The patient's own half of the nutrition timetable.
 *
 * Clinicians assign plans through {@see DoctorMealPlansController}; this
 * controller lets the patient add meals they intend to eat and record whether
 * they actually followed what was planned. A patient may only ever delete or
 * edit a plan they authored themselves — a clinician's instruction is theirs
 * to withdraw — but adherence can be logged against any plan on their record,
 * because that is the whole point of tracking it.
 */
class PatientMealPlansController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $this->validatePlan($request, required: true);
        $patient = $request->user();

        $plan = MealPlan::create([
            'patient_user_id' => $patient->id,
            'assigned_by_user_id' => null,
            'source' => MealPlan::SOURCE_PATIENT,
            'title' => $data['title'],
            'meal_type' => $data['meal_type'],
            'description' => $data['description'] ?? null,
            'items' => $data['items'] ?? null,
            'calories' => $data['calories'] ?? null,
            'protein' => $data['protein'] ?? null,
            'carbs' => $data['carbs'] ?? null,
            'fat' => $data['fat'] ?? null,
            'notes' => $data['notes'] ?? null,
            'condition_tag' => $data['condition_tag'] ?? null,
            'scheduled_for' => $data['scheduled_for'] ?? now()->toDateString(),
            'serve_time' => $data['serve_time'] ?? null,
            'adherence' => 'pending',
            'assigned_at' => now(),
        ]);

        return $this->success(
            ['meal_plan' => $plan->fresh(['patient', 'assignedBy'])->toApiArray()],
            'Meal added to your plan.',
            201,
        );
    }

    public function update(Request $request, MealPlan $mealPlan)
    {
        $this->authorizeOwnPlan($request, $mealPlan);
        $data = $this->validatePlan($request, required: false);

        $mealPlan->update(array_filter(
            $data,
            static fn ($value) => $value !== null,
        ));

        return $this->success(
            ['meal_plan' => $mealPlan->fresh(['patient', 'assignedBy'])->toApiArray()],
            'Meal updated.',
        );
    }

    public function destroy(Request $request, MealPlan $mealPlan)
    {
        $this->authorizeOwnPlan($request, $mealPlan);
        $mealPlan->delete();

        return $this->success(null, 'Meal removed from your plan.');
    }

    /**
     * Record whether the patient followed a planned meal. Works on
     * clinician-assigned plans too — that is the progress the care team reads.
     */
    public function log(Request $request, MealPlan $mealPlan)
    {
        if ($mealPlan->patient_user_id !== $request->user()->id) {
            return $this->error('Meal plan not found.', 404);
        }

        $data = $request->validate([
            'adherence' => 'required|string|in:'.implode(',', MealPlan::ADHERENCE),
            'patient_note' => 'nullable|string|max:500',
        ]);

        $mealPlan->update([
            'adherence' => $data['adherence'],
            'patient_note' => $data['patient_note'] ?? $mealPlan->patient_note,
            'logged_at' => $data['adherence'] === 'pending' ? null : now(),
        ]);

        return $this->success(
            ['meal_plan' => $mealPlan->fresh(['patient', 'assignedBy'])->toApiArray()],
            'Progress saved.',
        );
    }

    /**
     * @return array<string, mixed>
     */
    private function validatePlan(Request $request, bool $required): array
    {
        $rule = $required ? 'required' : 'nullable';

        return $request->validate([
            'title' => $rule.'|string|max:120',
            'meal_type' => $rule.'|string|in:breakfast,lunch,dinner,snack,general',
            'description' => 'nullable|string|max:500',
            'items' => 'nullable|array|max:30',
            'items.*' => 'string|max:120',
            'calories' => 'nullable|integer|min:0|max:10000',
            'protein' => 'nullable|string|max:32',
            'carbs' => 'nullable|string|max:32',
            'fat' => 'nullable|string|max:32',
            'notes' => 'nullable|string|max:500',
            'condition_tag' => 'nullable|string|max:120',
            'scheduled_for' => 'nullable|date',
            'serve_time' => ['nullable', 'string', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
        ]);
    }

    private function authorizeOwnPlan(Request $request, MealPlan $mealPlan): void
    {
        abort_unless(
            $mealPlan->patient_user_id === $request->user()->id
                && $mealPlan->source === MealPlan::SOURCE_PATIENT,
            403,
            'Only meals you added yourself can be changed here.',
        );
    }
}
