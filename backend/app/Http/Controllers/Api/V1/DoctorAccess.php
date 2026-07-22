<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\User;

/**
 * Small static helper shared by every Doctor* controller — owns the
 * "which patients can this doctor see" rule and the audit-log shortcut.
 *
 * Doctors only see patients they are currently assigned to via
 * care_assignments (ended_at IS NULL). Admins are intentionally NOT
 * granted blanket access here — admin routes live elsewhere.
 */
class DoctorAccess
{
    public static function caseloadPatientIds(User $doctor): array
    {
        $provider = CareProvider::where('user_id', $doctor->id)->first();
        if (! $provider) return [];

        return CareAssignment::where('provider_id', $provider->id)
            ->whereNull('ended_at')
            ->pluck('patient_user_id')
            ->all();
    }

    public static function assertCaseload(User $doctor, int $patientUserId): void
    {
        abort_unless(
            in_array($patientUserId, self::caseloadPatientIds($doctor), true),
            403,
            'Patient not in your caseload.'
        );
    }

    public static function audit(User $doctor, string $action, string $target, string $category = 'activity'): void
    {
        AuditEntry::create([
            'actor_user_id' => $doctor->id,
            'actor_label' => 'Dr. '.$doctor->fullName(),
            'action' => $action,
            'target' => $target,
            'category' => $category,
            'happened_at' => now(),
        ]);
    }
}
