<?php

namespace App\Support;

use App\Models\User;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use App\Services\VitalAlertNotifier;

/**
 * The one place a vital reading is written.
 *
 * Recording a reading is not an insert. The value has to be graded against
 * the patient's own range override — falling back to the catalog default —
 * and a warning or critical grade has to raise the alert that reaches the
 * care team. The patient endpoint did all of that inline, so the moment staff
 * needed to log a reading on a patient's behalf the choice was to duplicate it
 * or to let staff-entered readings quietly skip the alerting that is the whole
 * point of remote monitoring.
 *
 * @phpstan-type ReadingInput array{vital_key: string, value: float|int|string,
 *     secondary_value?: float|int|string|null, recorded_at?: string|null,
 *     note?: string|null}
 */
final class VitalRecorder
{
    /**
     * Grades and stores one reading for [$patient], then raises any alert.
     *
     * [$recordedBy] is the staff member entering it on the patient's behalf,
     * and null when the patient logged it themselves.
     *
     * @param  array<string, mixed>  $data
     */
    public static function record(
        User $patient,
        array $data,
        ?User $recordedBy = null,
        ?string $recordedByLabel = null,
    ): VitalReading {
        // A patient's own range override wins over the catalog default: the
        // thresholds a clinician set for this person are what "normal" means
        // for them, and grading against the generic band would raise alerts
        // nobody wants and miss the ones they do.
        $range = $patient->vitalRangeOverrides()
            ->where('vital_key', $data['vital_key'])
            ->first()
            ?? VitalCatalog::where('vital_key', $data['vital_key'])->first();

        $risk = $range
            ? VitalRisk::assess((float) $data['value'], $range)
            : 'unknown';

        $reading = $patient->vitalReadings()->create([
            'vital_key' => $data['vital_key'],
            'value' => $data['value'],
            'secondary_value' => $data['secondary_value'] ?? null,
            'recorded_at' => $data['recorded_at'] ?? now(),
            'note' => $data['note'] ?? null,
            'risk' => $risk,
            'recorded_by_user_id' => $recordedBy?->id,
            'recorded_by_label' => $recordedBy === null ? null : $recordedByLabel,
        ]);

        // Staff-entered readings alert exactly as the patient's own do. A
        // critical value is critical whoever typed it.
        VitalAlertNotifier::notify($patient, $reading);

        return $reading;
    }

    /** Validation rules shared by the patient and staff entry points. */
    public static function rules(): array
    {
        return [
            'vital_key' => 'required|string',
            'value' => 'required|numeric',
            'secondary_value' => 'nullable|numeric',
            'recorded_at' => 'nullable|date',
            'note' => 'nullable|string',
        ];
    }
}
