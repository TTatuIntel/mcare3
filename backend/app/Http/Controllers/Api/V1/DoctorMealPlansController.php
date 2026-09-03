<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MealPlan;
use App\Models\User;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class DoctorMealPlansController extends Controller
{
    use ApiResponse;

    /**
     * Assign nutrition. One call can cover several patients and several days:
     * `patient_user_ids` and `scheduled_for` both accept a list, and the plan
     * is written once per patient per day. A single-patient, single-day assign
     * is just the degenerate case, so the older payload shape still works.
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required_without:patient_user_ids|exists:users,id',
            'patient_user_ids' => 'required_without:patient_user_id|array|min:1|max:100',
            'patient_user_ids.*' => 'exists:users,id',
            'title' => 'required|string|max:120',
            'meal_type' => 'required|string|in:breakfast,lunch,dinner,snack,general',
            'description' => 'nullable|string|max:500',
            'items' => 'nullable|array|max:30',
            'items.*' => 'string|max:120',
            'calories' => 'nullable|integer|min:0|max:10000',
            'protein' => 'nullable|string|max:32',
            'carbs' => 'nullable|string|max:32',
            'fat' => 'nullable|string|max:32',
            'notes' => 'nullable|string|max:500',
            'condition_tag' => 'nullable|string|max:120',
            'serve_time' => ['nullable', 'string', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
            'scheduled_for' => 'nullable',
            'scheduled_for.*' => 'date',
        ]);

        $doctor = $request->user();

        $patientIds = $data['patient_user_ids'] ?? [$data['patient_user_id']];
        $patients = User::whereIn('id', array_unique($patientIds))->get();

        foreach ($patients as $patient) {
            if ($patient->role !== 'patient') {
                return $this->error('Meal plans can only be assigned to patients.', 422);
            }
            if (! $this->doctorHasPatient($doctor, $patient)) {
                return $this->error('One or more patients are not on your caseload.', 403);
            }
        }

        $days = $this->scheduledDays($data['scheduled_for'] ?? null);

        $created = [];
        foreach ($patients as $patient) {
            foreach ($days as $day) {
                $plan = MealPlan::create([
                    'patient_user_id' => $patient->id,
                    'assigned_by_user_id' => $doctor->id,
                    'source' => MealPlan::SOURCE_CARE_TEAM,
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
                    'scheduled_for' => $day,
                    'serve_time' => $data['serve_time'] ?? null,
                    'adherence' => 'pending',
                    'assigned_at' => now(),
                ]);
                $plan->load(['patient', 'assignedBy']);
                $created[] = $plan->toApiArray();
            }
        }

        return $this->success(
            [
                // Single-assign callers read `meal_plan`; batch callers read
                // the full list. Both are always present.
                'meal_plan' => $created[0] ?? null,
                'meal_plans' => $created,
            ],
            count($created) === 1
                ? 'Meal plan assigned.'
                : count($created).' meal plans assigned.',
            201,
        );
    }

    /**
     * Normalises the requested schedule into a list of distinct days. An
     * absent schedule means today, which is how assignment behaved before
     * meal plans carried a date.
     *
     * @return list<string>
     */
    private function scheduledDays(mixed $raw): array
    {
        $values = match (true) {
            $raw === null || $raw === '' => [now()->toDateString()],
            is_array($raw) => $raw,
            default => [$raw],
        };

        $days = [];
        foreach ($values as $value) {
            $day = Carbon::parse($value)->toDateString();
            if (! in_array($day, $days, true)) {
                $days[] = $day;
            }
        }

        return $days ?: [now()->toDateString()];
    }

    public function destroy(Request $request, MealPlan $mealPlan)
    {
        $doctor = $request->user();
        $patient = $mealPlan->patient;

        if (! $patient || ! $this->doctorHasPatient($doctor, $patient)) {
            return $this->error('Meal plan not found on your caseload.', 404);
        }

        $mealPlan->delete();

        return $this->success(null, 'Meal plan removed.');
    }

    private function doctorHasPatient(User $doctor, User $patient): bool
    {
        $provider = CareProvider::where('user_id', $doctor->id)->first();
        if (! $provider) {
            return false;
        }

        return CareAssignment::query()
            ->where('provider_id', $provider->id)
            ->where('patient_user_id', $patient->id)
            ->whereNull('ended_at')
            ->exists();
    }
}
