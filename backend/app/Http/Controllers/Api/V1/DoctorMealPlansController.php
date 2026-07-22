<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\MealPlan;
use App\Models\User;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorMealPlansController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|exists:users,id',
            'title' => 'required|string|max:120',
            'meal_type' => 'required|string|in:breakfast,lunch,dinner,snack,general',
            'description' => 'nullable|string|max:500',
            'calories' => 'nullable|integer|min:0|max:10000',
            'protein' => 'nullable|string|max:32',
            'carbs' => 'nullable|string|max:32',
            'fat' => 'nullable|string|max:32',
            'notes' => 'nullable|string|max:500',
        ]);

        $doctor = $request->user();
        $patient = User::findOrFail($data['patient_user_id']);

        if ($patient->role !== 'patient') {
            return $this->error('Meal plans can only be assigned to patients.', 422);
        }

        if (! $this->doctorHasPatient($doctor, $patient)) {
            return $this->error('Patient is not on your caseload.', 403);
        }

        $plan = MealPlan::create([
            'patient_user_id' => $patient->id,
            'assigned_by_user_id' => $doctor->id,
            'title' => $data['title'],
            'meal_type' => $data['meal_type'],
            'description' => $data['description'] ?? null,
            'calories' => $data['calories'] ?? null,
            'protein' => $data['protein'] ?? null,
            'carbs' => $data['carbs'] ?? null,
            'fat' => $data['fat'] ?? null,
            'notes' => $data['notes'] ?? null,
            'assigned_at' => now(),
        ]);

        $plan->load(['patient', 'assignedBy']);

        return $this->success(
            ['meal_plan' => $plan->toApiArray()],
            'Meal plan assigned.',
            201,
        );
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
