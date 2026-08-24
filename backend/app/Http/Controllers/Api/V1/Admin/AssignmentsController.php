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
 *
 * Approving a care request writes the same rows via
 * {@see CareRequestsController::route()} — this controller covers the
 * admin-initiated pairings made directly from the merged admin screen.
 */
class AssignmentsController extends Controller
{
    use ApiResponse;

    private const ROLES = ['Primary', 'Consulting', 'Specialist'];

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $query = CareAssignment::query()
            ->with(['patient', 'provider', 'assigner'])
            ->orderByDesc('assigned_at');

        if (! $request->boolean('include_ended')) {
            $query->whereNull('ended_at');
        }
        if ($patientId = $request->query('patient_id')) {
            $query->where('patient_user_id', $patientId);
        }
        if ($providerId = $request->query('provider_id')) {
            $query->where('provider_id', $providerId);
        }
        if ($role = $request->query('role')) {
            $query->where('role', $role);
        }
        if ($term = trim((string) $request->query('query', ''))) {
            $query->where(function ($q) use ($term) {
                $q->whereHas('patient', function ($p) use ($term) {
                    $p->where('first_name', 'like', "%{$term}%")
                        ->orWhere('last_name', 'like', "%{$term}%");
                })->orWhereHas('provider', function ($p) use ($term) {
                    $p->where('name', 'like', "%{$term}%")
                        ->orWhere('specialty', 'like', "%{$term}%");
                });
            });
        }

        $assignments = $query->limit(500)->get()->map->toAdminArray();

        return $this->success(['assignments' => $assignments]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|exists:users,id',
            'provider_id' => 'nullable|exists:care_providers,id',
            'provider_user_id' => 'nullable|exists:users,id',
            'role' => 'nullable|string|in:'.implode(',', self::ROLES),
            'reason' => 'nullable|string|max:280',
        ]);

        $providerId = $data['provider_id'] ?? null;

        // Callers may identify the doctor by their user id (from the directory)
        // rather than the care_providers row id. Resolve to a CareProvider so
        // downstream gating (DoctorAccess) works uniformly.
        if ($providerId === null && ! empty($data['provider_user_id'])) {
            $providerId = CareProvider::resolveForUser($data['provider_user_id'])->id;
        }

        if ($providerId === null) {
            return $this->error('Missing provider_id or provider_user_id.', 422);
        }

        $existing = CareAssignment::query()
            ->where('patient_user_id', $data['patient_user_id'])
            ->where('provider_id', $providerId)
            ->whereNull('ended_at')
            ->first();

        if ($existing) {
            return $this->error('Assignment already exists.', 422);
        }

        $assignment = CareAssignment::create([
            'patient_user_id' => $data['patient_user_id'],
            'provider_id' => $providerId,
            'role' => $data['role'] ?? 'Primary',
            'assigned_at' => now(),
            'assigned_reason' => trim((string) ($data['reason'] ?? '')) ?: null,
            'assigned_by' => $request->user()?->id,
        ]);

        $patient = User::find($data['patient_user_id']);
        $provider = CareProvider::find($providerId);

        $this->audit->record(
            $request->user(),
            'assignment.created',
            ($patient?->fullName() ?? 'Patient').' ↔ '.($provider?->name ?? 'Provider'),
            'activity',
            [
                'assignment_id' => $assignment->id,
                'provider_id' => $providerId,
                'role' => $assignment->role,
                'reason' => $assignment->assigned_reason,
            ],
        );

        return $this->success(
            ['assignment' => $assignment->load(['patient', 'provider', 'assigner'])->toAdminArray()],
            'Assigned.',
            201,
        );
    }

    public function destroy(Request $request, CareAssignment $assignment)
    {
        $data = $request->validate([
            'reason' => 'nullable|string|max:280',
        ]);

        $assignment->update([
            'ended_at' => now(),
            'ended_reason' => trim((string) ($data['reason'] ?? '')) ?: null,
            'ended_by' => $request->user()?->id,
        ]);

        $this->audit->record(
            $request->user(),
            'assignment.removed',
            ($assignment->patient?->fullName() ?? 'Patient').' ↔ '.($assignment->provider?->name ?? 'Provider'),
            'activity',
            ['assignment_id' => $assignment->id, 'reason' => $assignment->ended_reason],
        );

        return $this->success(['id' => (string) $assignment->id], 'Removed.');
    }
}
