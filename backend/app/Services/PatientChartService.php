<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\ClinicalReport;
use App\Models\MealPlan;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Models\MedicalDocument;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalReading;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

/**
 * One patient's clinical record over a chosen period.
 *
 * The staff patient sheet used to show identity, a health score and a list of
 * conditions — the account, not the patient. Whoever opened it mid-emergency
 * still had to leave for medications, for the last readings, for who is on
 * the care team, for the next of kin to call. This assembles all of it in one
 * windowed read, so the chart can be filtered to a period and every section
 * answers from the same window.
 *
 * Section keys deliberately match {@see \App\Support\PatientReportSections}:
 * what a clinician reads here is what they can then tick into a report.
 *
 * Distinct from {@see UserDossierService}, which builds the *complete*
 * account record (login history, approvals, tickets) with no period at all.
 * This is the clinical chart: windowed, summarised, and readable by a doctor
 * on their own caseload rather than by admin alone.
 */
class PatientChartService
{
    /** Readings kept per vital for the trend line — enough to see shape. */
    private const POINTS_PER_VITAL = 60;

    /** @return array<string, mixed> */
    public function build(User $patient, CarbonInterface $from, CarbonInterface $to): array
    {
        $patient->loadMissing(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        $readings = VitalReading::where('user_id', $patient->id)
            ->whereBetween('recorded_at', [$from, $to])
            ->orderByDesc('recorded_at')
            ->limit(1500)
            ->get();

        $alerts = AppNotification::where('user_id', $patient->id)
            ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
            ->whereBetween('created_at', [$from, $to])
            ->orderByDesc('created_at')
            ->limit(120)
            ->get();

        $sos = SosEvent::where('user_id', $patient->id)
            ->whereBetween('triggered_at', [$from, $to])
            ->orderByDesc('triggered_at')
            ->limit(60)
            ->get();

        $appointments = Appointment::where('user_id', $patient->id)
            ->whereBetween('scheduled_at', [$from, $to])
            ->orderByDesc('scheduled_at')
            ->limit(120)
            ->get();

        // A medication started before the window but still being taken is the
        // most clinically relevant thing on the list. Filtering it out because
        // it was prescribed last year would be a reporting error, not tidiness.
        $medications = Medication::where('user_id', $patient->id)
            ->where(function ($q) use ($from, $to) {
                $q->where('active', true)
                    ->orWhereBetween('start_date', [$from, $to])
                    ->orWhereBetween('end_date', [$from, $to]);
            })
            ->orderByDesc('active')
            ->orderByDesc('start_date')
            ->limit(120)
            ->get();

        $meals = MealPlan::where('patient_user_id', $patient->id)
            ->whereBetween('assigned_at', [$from, $to])
            ->orderByDesc('assigned_at')
            ->limit(120)
            ->get();

        $documents = MedicalDocument::where('user_id', $patient->id)
            ->whereBetween('uploaded_at', [$from, $to])
            ->orderByDesc('uploaded_at')
            ->limit(120)
            ->get();

        $notes = ClinicalReport::with('author')
            ->where('patient_user_id', $patient->id)
            ->whereBetween('created_at', [$from, $to])
            ->orderByDesc('created_at')
            ->limit(120)
            ->get();

        // The care team and next of kin are answers to "who do I call", not
        // period data. They are never windowed.
        $careTeam = CareAssignment::with(['provider.user', 'assigner'])
            ->where('patient_user_id', $patient->id)
            ->whereNull('ended_at')
            ->orderByDesc('assigned_at')
            ->get();

        $adherence = $this->adherence($patient, $from, $to);

        return [
            'patient' => [
                'id' => (string) $patient->id,
                'unique_id' => $patient->unique_id,
                'name' => $patient->fullName(),
                'email' => $patient->email,
                'phone' => $patient->phone,
                'status' => $patient->approvalStatusToClient(),
                'joined_at' => $patient->created_at?->toIso8601String(),
                'avatar_url' => $patient->avatarUrl(),
            ],
            'window' => [
                'from' => $from->toIso8601String(),
                'to' => $to->toIso8601String(),
                'days' => max(1, $from->diffInDays($to)),
            ],
            'health' => $patient->healthProfile?->toApiArray(),
            'has_health_profile' => $patient->healthProfile !== null,
            'location' => $this->location($patient, $sos),
            'next_of_kin' => $patient->emergencyContacts
                ->sortBy('priority')
                ->map->toApiArray()
                ->values()
                ->all(),
            'care_team' => $careTeam->map->toAdminArray()->all(),
            'assigned_vitals' => $patient->assignedVitals->pluck('vital_key')->values()->all(),
            'vitals' => $this->vitals($patient, $readings),
            'alerts' => $alerts->map(fn (AppNotification $n) => [
                'id' => (string) $n->id,
                'kind' => $n->kind,
                'title' => $n->title,
                'body' => $n->body,
                'read' => (bool) $n->read,
                'resolved' => (bool) $n->resolved,
                'created_at' => $n->created_at?->toIso8601String(),
            ])->all(),
            'sos' => $sos->map->toApiArray()->all(),
            'medications' => $medications->map(fn (Medication $m) => $m->toApiArray() + [
                'prescribed_by_name' => $m->prescribedByUser?->fullName() ?? $m->prescribed_by,
            ])->all(),
            'meals' => $meals->map->toApiArray()->all(),
            'appointments' => $appointments->map->toApiArray()->all(),
            'documents' => $documents->map->toApiArray()->all(),
            'notes' => $notes->map(fn (ClinicalReport $r) => $r->toApiArray() + [
                'author_name' => $r->author?->fullName(),
            ])->all(),
            'summary' => $this->summary(
                $readings,
                $alerts,
                $sos,
                $appointments,
                $medications,
                $meals,
                $documents,
                $notes,
                $adherence,
            ),
        ];
    }

    /**
     * Where the patient was last known to be. The health profile carries a
     * home address; an SOS carries where they actually were when they raised
     * it, which is the one a responder needs.
     *
     * @param  Collection<int, SosEvent>  $sos
     * @return array<string, mixed>
     */
    private function location(User $patient, Collection $sos): array
    {
        $located = $sos->first(
            fn (SosEvent $e) => $e->latitude !== null && $e->longitude !== null
        );

        return [
            'address' => $patient->healthProfile?->address,
            'last_seen_label' => $located?->location_label,
            'latitude' => $located?->latitude,
            'longitude' => $located?->longitude,
            'at' => $located?->triggered_at?->toIso8601String(),
            'source' => $located === null ? 'profile' : 'sos',
            'consent' => (bool) ($patient->healthProfile?->location_consent ?? false),
        ];
    }

    /**
     * Per-vital trend over the window: the points to draw, the latest value,
     * how much of the window sat in range, and the direction of travel.
     *
     * @param  Collection<int, VitalReading>  $readings
     * @return list<array<string, mixed>>
     */
    private function vitals(User $patient, Collection $readings): array
    {
        $keys = array_values(array_unique(array_merge(
            $patient->assignedVitals->pluck('vital_key')->all(),
            $readings->pluck('vital_key')->unique()->all(),
        )));

        $out = [];
        foreach ($keys as $key) {
            /** @var Collection<int, VitalReading> $forVital */
            $forVital = $readings->where('vital_key', $key)->values();
            $latest = $forVital->first();
            $inRange = $forVital->where('risk', 'normal')->count();

            $out[] = [
                'key' => $key,
                'count' => $forVital->count(),
                'in_range' => $inRange,
                'in_range_pct' => $forVital->count() === 0
                    ? null
                    : (int) round($inRange / $forVital->count() * 100),
                'latest' => $latest === null ? null : [
                    'value' => $latest->value,
                    'secondary_value' => $latest->secondary_value,
                    'display_value' => $latest->displayValue(),
                    'risk' => $latest->risk,
                    'recorded_at' => $latest->recorded_at?->toIso8601String(),
                ],
                'trend' => $this->trend($forVital),
                // Oldest first: the client draws left to right.
                'points' => $forVital
                    ->take(self::POINTS_PER_VITAL)
                    ->reverse()
                    ->map(fn (VitalReading $r) => [
                        'value' => (float) $r->value,
                        'secondary_value' => $r->secondary_value === null
                            ? null
                            : (float) $r->secondary_value,
                        'risk' => $r->risk,
                        'at' => $r->recorded_at?->toIso8601String(),
                    ])
                    ->values()
                    ->all(),
            ];
        }

        return $out;
    }

    /**
     * Newest half against oldest half. Fewer than four readings is not a
     * trend, and calling it one would be the chart inventing a finding.
     *
     * @param  Collection<int, VitalReading>  $forVital
     */
    private function trend(Collection $forVital): string
    {
        if ($forVital->count() < 4) {
            return 'flat';
        }

        $half = (int) floor($forVital->count() / 2);
        $newer = (float) $forVital->take($half)->avg('value');
        $older = (float) $forVital->slice($half)->avg('value');
        if ($older == 0.0) {
            return 'flat';
        }

        $delta = ($newer - $older) / abs($older);

        return match (true) {
            $delta > 0.05 => 'up',
            $delta < -0.05 => 'down',
            default => 'flat',
        };
    }

    /** @return array{taken: int, scheduled: int, pct: int|null} */
    private function adherence(User $patient, CarbonInterface $from, CarbonInterface $to): array
    {
        $doses = MedicationDose::where('user_id', $patient->id)
            ->whereBetween('scheduled_at', [$from, $to])
            ->get();

        $scheduled = $doses->count();
        $taken = $doses->where('status', 'taken')->count();

        return [
            'taken' => $taken,
            'scheduled' => $scheduled,
            'pct' => $scheduled === 0 ? null : (int) round($taken / $scheduled * 100),
        ];
    }

    /**
     * @param  Collection<int, VitalReading>  $readings
     * @param  Collection<int, AppNotification>  $alerts
     * @param  Collection<int, SosEvent>  $sos
     * @param  Collection<int, Appointment>  $appointments
     * @param  Collection<int, Medication>  $medications
     * @param  Collection<int, MealPlan>  $meals
     * @param  Collection<int, MedicalDocument>  $documents
     * @param  Collection<int, ClinicalReport>  $notes
     * @param  array{taken: int, scheduled: int, pct: int|null}  $adherence
     * @return array<string, mixed>
     */
    private function summary(
        Collection $readings,
        Collection $alerts,
        Collection $sos,
        Collection $appointments,
        Collection $medications,
        Collection $meals,
        Collection $documents,
        Collection $notes,
        array $adherence,
    ): array {
        $inRange = $readings->where('risk', 'normal')->count();

        return [
            'readings' => $readings->count(),
            // The period's health percentage: how much of what was measured
            // sat in range. Null rather than 100 when nothing was measured —
            // an unmonitored patient is not a healthy one.
            'in_range_pct' => $readings->count() === 0
                ? null
                : (int) round($inRange / $readings->count() * 100),
            'alerts' => $alerts->count(),
            'alerts_critical' => $alerts->where('kind', 'vital_critical')->count(),
            'alerts_unresolved' => $alerts->where('resolved', false)->count(),
            'sos' => $sos->count(),
            'sos_open' => $sos->whereIn('status', ['active', 'acknowledged'])->count(),
            'appointments' => $appointments->count(),
            'appointments_kept' => $appointments->where('status', 'completed')->count(),
            'appointments_missed' => $appointments->where('status', 'missed')->count(),
            'medications_active' => $medications->where('active', true)->count(),
            'adherence_pct' => $adherence['pct'],
            'doses_taken' => $adherence['taken'],
            'doses_scheduled' => $adherence['scheduled'],
            'meals' => $meals->count(),
            'documents' => $documents->count(),
            'notes' => $notes->count(),
        ];
    }
}
