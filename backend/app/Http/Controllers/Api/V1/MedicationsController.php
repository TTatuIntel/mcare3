<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class MedicationsController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:160',
            'dosage' => 'required|string|max:60',
            'frequency' => 'required|string|max:120',
            'form' => 'nullable|string|max:60',
            'instructions' => 'nullable|string',
            'prescribed_by' => 'nullable|string|max:160',
            'start_date' => 'required|date',
            'end_date' => 'nullable|date|after_or_equal:start_date',
            'expiry_date' => 'nullable|date',
            'refills_left' => 'nullable|integer|min:0',
            'source' => 'nullable|string|in:doctorPrescribed,patientAdded',
        ]);

        $med = $request->user()->medications()->create([
            ...$data,
            'source' => $data['source'] ?? 'patientAdded',
            'active' => true,
        ]);

        return $this->success(['medication' => $med->toApiArray()], 'Medication saved.', 201);
    }

    public function update(Request $request, Medication $medication)
    {
        $this->authorizeOwnership($request, $medication);
        $data = $request->validate([
            'name' => 'nullable|string',
            'dosage' => 'nullable|string',
            'frequency' => 'nullable|string',
            'instructions' => 'nullable|string',
            'refills_left' => 'nullable|integer|min:0',
            'expiry_date' => 'nullable|date',
            'active' => 'nullable|boolean',
        ]);
        $medication->update(array_filter($data, fn ($v) => $v !== null));
        return $this->success(['medication' => $medication->fresh()->toApiArray()], 'Medication updated.');
    }

    public function destroy(Request $request, Medication $medication)
    {
        $this->authorizeOwnership($request, $medication);
        $medication->update(['active' => false]);
        return $this->success(null, 'Medication archived.');
    }

    public function recordDose(Request $request, MedicationDose $dose)
    {
        if ($dose->user_id !== $request->user()->id) {
            return $this->error('Not allowed.', 403);
        }
        $data = $request->validate([
            'status' => 'required|string|in:pending,taken,skipped,missed',
            'taken_at' => 'nullable|date',
        ]);
        $dose->update([
            'status' => $data['status'],
            'taken_at' => $data['taken_at'] ?? ($data['status'] === 'taken' ? now() : null),
        ]);
        return $this->success(['dose' => $dose->fresh()->toApiArray()], 'Dose updated.');
    }

    private function authorizeOwnership(Request $request, Medication $med): void
    {
        abort_unless($med->user_id === $request->user()->id, 403, 'Not allowed.');
    }
}
