<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\ClinicalReport;
use App\Models\MealPlan;
use App\Models\Medication;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use App\Support\ApiResponse;
use App\Support\VitalAlertPayload;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

/**
 * Returns the full doctor session in a single payload — caseload, alerts,
 * appointments, prescriptions, reports, vital report requests, care queue.
 * Care-request triage is not part of it: that is an admin / mCare-assistant
 * responsibility, and the doctor only ever sees the care team assigned.
 *
 * Shape mirrors what `StaffState.seedDemo()` produces in the Flutter mock
 * layer, so the existing doctor screens can rehydrate without changes.
 */
class DoctorSessionController extends Controller
{
    use ApiResponse;

    public function show(Request $request)
    {
        $doctor = $request->user();

        // Resolve, don't look up: without a `care_providers` row the doctor's
        // caseload comes back empty no matter who was assigned to them.
        $provider = CareProvider::resolveForUser($doctor->id);
        $assignments = $provider
            ? CareAssignment::where('provider_id', $provider->id)
                ->whereNull('ended_at')
                ->with('patient.healthProfile')
                ->get()
            : collect();

        $patients = $assignments
            ->map(fn (CareAssignment $a) => $a->patient)
            ->filter()
            ->unique('id')
            ->values();
        $patientIds = $patients->pluck('id')->all();

        $latestReadings = $this->latestReadingsFor($patientIds);
        $unreadAlertCounts = $patientIds
            ? AppNotification::query()
                ->whereIn('user_id', $patientIds)
                ->where('read', false)
                ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
                ->selectRaw('user_id, COUNT(*) as aggregate')
                ->groupBy('user_id')
                ->pluck('aggregate', 'user_id')
            : collect();

        $caseload = $patients->map(function (User $p) use ($latestReadings, $unreadAlertCounts, $doctor) {
            $r = $latestReadings[$p->id] ?? null;

            return [
                'id' => (string) $p->id,
                'unique_id' => $p->unique_id,
                'name' => $p->fullName(),
                'age' => optional($p->healthProfile)->date_of_birth
                    ? Carbon::parse($p->healthProfile->date_of_birth)->age
                    : null,
                'sex' => optional($p->healthProfile)->gender,
                'condition' => is_array(optional($p->healthProfile)->chronic_conditions)
                    ? implode(' · ', $p->healthProfile->chronic_conditions)
                    : '',
                'risk' => $r['risk'] ?? 'unknown',
                'last_reading_at' => $r['recorded_at'] ?? null,
                'assigned_doctor' => 'Dr. '.$doctor->fullName(),
                'unread_alerts' => (int) ($unreadAlertCounts[$p->id] ?? 0),
            ];
        })->all();

        $alerts = $patientIds
            ? AppNotification::whereIn('user_id', $patientIds)
                ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(function (AppNotification $n) use ($patients) {
                    $patient = $patients->firstWhere('id', $n->user_id);

                    return VitalAlertPayload::alertToApiArray($n, [
                        'patient_id' => (string) $n->user_id,
                        'patient_name' => $patient ? $patient->fullName() : '',
                    ]);
                })
                ->all()
            : [];

        $appointments = Appointment::with('user')
            ->where('doctor_user_id', $doctor->id)
            ->orderBy('scheduled_at')
            ->limit(200)
            ->get()
            ->map(function (Appointment $a) {
                $arr = $a->toApiArray();
                $arr['patient_id'] = (string) $a->user_id;
                $arr['patient_name'] = optional($a->user)->fullName();

                return $arr;
            })
            ->all();

        $prescriptions = Medication::with('user')
            ->where('prescribed_by_user_id', $doctor->id)
            ->orderByDesc('start_date')
            ->limit(200)
            ->get()
            ->map(function (Medication $m) {
                return [
                    'id' => (string) $m->id,
                    'patient_id' => (string) $m->user_id,
                    'patient_name' => optional($m->user)->fullName(),
                    'drug' => $m->name,
                    'dosage' => $m->dosage,
                    'frequency' => $m->frequency,
                    'instructions' => $m->instructions,
                    'start_date' => $m->start_date?->toDateString(),
                    'end_date' => $m->end_date?->toDateString(),
                    'status' => $m->active ? 'Active' : 'Archived',
                ];
            })
            ->all();

        $reports = ClinicalReport::with('patient')
            ->where('author_user_id', $doctor->id)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(function (ClinicalReport $r) {
                $arr = $r->toApiArray();
                $arr['patient_name'] = optional($r->patient)->fullName();

                return $arr;
            })
            ->all();

        $vitalRequests = $patientIds
            ? VitalReportRequest::whereIn('user_id', $patientIds)
                ->whereIn('status', ['pending', 'in_progress'])
                ->orderByDesc('created_at')
                ->get()
                ->map(function (VitalReportRequest $r) use ($patients) {
                    $arr = $r->toApiArray();
                    $arr['patient_id'] = (string) $r->user_id;
                    $arr['patient_name'] = optional($patients->firstWhere('id', $r->user_id))->fullName();

                    return $arr;
                })
                ->all()
            : [];

        // Pending care requests are deliberately not shipped here. Triage
        // belongs to admins and mCare assistants; a doctor sees the care team
        // they were assigned to, so a request they cannot decide on is noise
        // at best and a disclosure of an undecided referral at worst.

        $sosEvents = $patientIds
            ? SosEvent::with(['user', 'responseActions.user'])
                ->whereIn('user_id', $patientIds)
                ->whereIn('status', ['active', 'acknowledged'])
                ->orderByDesc('triggered_at')
                ->get()
                ->map(function (SosEvent $e) {
                    $arr = $e->toApiArray();
                    $arr['patient_id'] = (string) $e->user_id;
                    $arr['patient_name'] = $e->user?->fullName() ?? '';

                    return $arr;
                })
                ->all()
            : [];

        $vitalReadings = $patientIds
            ? VitalReading::with('user')
                ->whereIn('user_id', $patientIds)
                ->orderByDesc('recorded_at')
                ->limit(1000)
                ->get()
                ->map(function (VitalReading $r) use ($patients) {
                    $patient = $patients->firstWhere('id', $r->user_id);

                    return array_merge($r->toApiArray(), [
                        'patient_id' => (string) $r->user_id,
                        'patient_name' => $patient ? $patient->fullName() : '',
                    ]);
                })
                ->all()
            : [];

        $notifications = AppNotification::query()
            ->where('user_id', $doctor->id)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map->toApiArray()
            ->all();

        return $this->success([
            'doctor' => array_merge($doctor->toApiArray(), [
                'display_name' => 'Dr. '.$doctor->fullName(),
                'provider_id' => $provider ? (string) $provider->id : null,
                'specialty' => $provider->specialty ?? null,
                'facility' => $provider->facility ?? null,
            ]),
            'caseload' => $caseload,
            'alerts' => $alerts,
            'notifications' => $notifications,
            'appointments' => $appointments,
            'prescriptions' => $prescriptions,
            'reports' => $reports,
            'vital_report_requests' => $vitalRequests,
            'care_requests' => [],
            'sos_events' => $sosEvents,
            'vital_readings' => $vitalReadings,
            'vital_catalog' => VitalCatalog::orderBy('vital_key')
                ->get()
                ->map->toApiArray()
                ->all(),
            'meal_plans' => $patientIds
                ? MealPlan::with(['patient', 'assignedBy'])
                    ->whereIn('patient_user_id', $patientIds)
                    ->orderByDesc('assigned_at')
                    ->get()
                    ->map->toApiArray()
                    ->all()
                : [],
            'kpis' => [
                'active_patients' => count($caseload),
                'open_alerts' => collect($alerts)->where('acknowledged', false)->count(),
                'pending_appointments' => collect($appointments)
                    ->where('status', 'scheduled')->count(),
                'pending_requests' => count($vitalRequests),
            ],
        ]);
    }

    /**
     * For each patient id, return the most recent vital reading as
     * ['risk' => ..., 'recorded_at' => ...].
     */
    private function latestReadingsFor(array $patientIds): array
    {
        if (! $patientIds) {
            return [];
        }

        $latestAt = VitalReading::query()
            ->whereIn('user_id', $patientIds)
            ->selectRaw('user_id, MAX(recorded_at) as latest_at')
            ->groupBy('user_id');

        return VitalReading::query()
            ->joinSub($latestAt, 'latest_readings', function ($join) {
                $join->on('vital_readings.user_id', '=', 'latest_readings.user_id')
                    ->on('vital_readings.recorded_at', '=', 'latest_readings.latest_at');
            })
            ->select('vital_readings.*')
            ->orderByDesc('vital_readings.id')
            ->get()
            ->groupBy('user_id')
            ->map(fn (Collection $rows) => [
                'risk' => $rows->first()->risk,
                'recorded_at' => $rows->first()->recorded_at?->toIso8601String(),
            ])
            ->all();
    }
}
