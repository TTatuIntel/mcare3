<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Bind patients to care providers (doctors / healthworkers). The
 * `care_assignments` row drives DoctorAccess caseload gating.
 */
class AssignmentsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $query = CareAssignment::query()
            ->with(['patient', 'provider'])
            ->whereNull('ended_at')
            ->orderByDesc('assigned_at');

        if ($patientId = $request->query('patient_id')) {
            $query->where('patient_user_id', $patientId);
        }
        if ($providerId = $request->query('provider_id')) {
            $query->where('provider_id', $providerId);
        }

        $assignments = $query->limit(500)->get()->map(function (CareAssignment $a) {
            $arr = $a->toApiArray();
            $arr['patient_name'] = $a->patient?->fullName();
            $arr['provider_name'] = $a->provider?->name;
            $arr['provider_specialty'] = $a->provider?->specialty;
            return $arr;
        });

        return $this->success(['assignments' => $assignments]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|exists:users,id',
            'provider_id' => 'required|exists:care_providers,id',
            'role' => 'nullable|string|max:32',
        ]);

        $existing = CareAssignment::query()
            ->where('patient_user_id', $data['patient_user_id'])
            ->where('provider_id', $data['provider_id'])
            ->whereNull('ended_at')
            ->first();

        if ($existing) {
            return $this->error('Assignment already exists.', 422);
        }

        $assignment = CareAssignment::create([
            'patient_user_id' => $data['patient_user_id'],
            'provider_id' => $data['provider_id'],
            'role' => $data['role'] ?? 'Primary',
            'assigned_at' => now(),
        ]);

        $patient = User::find($data['patient_user_id']);
        $provider = CareProvider::find($data['provider_id']);

        $this->audit->record(
            $request->user(),
            'assignment.created',
            ($patient?->fullName() ?? 'Patient').' ↔ '.($provider?->name ?? 'Provider'),
            'activity',
            ['assignment_id' => $assignment->id],
        );

        return $this->success(['assignment' => $assignment->toApiArray()], 'Assigned.', 201);
    }

    public function destroy(Request $request, CareAssignment $assignment)
    {
        $assignment->update(['ended_at' => now()]);

        $this->audit->record(
            $request->user(),
            'assignment.removed',
            ($assignment->patient?->fullName() ?? 'Patient').' ↔ '.($assignment->provider?->name ?? 'Provider'),
            'activity',
            ['assignment_id' => $assignment->id],
        );

        return $this->success(['id' => (string) $assignment->id], 'Removed.');
    }
}
