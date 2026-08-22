<?php

namespace App\Services;

use App\Events\VitalAlertBroadcast;
use App\Models\AppNotification;
use App\Models\User;
use App\Models\VitalReading;
use App\Support\VitalAlertPayload;

/**
 * Creates patient notifications when a vital reading is outside range.
 * Doctors see these via caseload alert sync (patient-owned notifications).
 *
 * README §7.1 — additionally fires [VitalAlertBroadcast] so subscribers on
 * `private-user.{id}` / `private-care-team.{patientId}` get the alert in
 * <2s. Kept additive: REST/poller path is unchanged; if BROADCAST_CONNECTION
 * is `log` or `null`, the broadcast is a no-op.
 */
class VitalAlertNotifier
{
    public static function notify(User $patient, VitalReading $reading): void
    {
        if (! in_array($reading->risk, ['warning', 'critical'], true)) {
            // A normal reading clears any open alerts for the same vital so the
            // patient inbox matches the client's auto-resolve behaviour and does
            // not resurface stale alerts on the next poll.
            AppNotification::where('user_id', $patient->id)
                ->whereIn('kind', ['vital_warning', 'vital_critical'])
                ->where('resolved', false)
                ->where('action_arguments->vital_key', $reading->vital_key)
                ->update([
                    'resolved' => true,
                    'resolved_at' => now(),
                    'read' => true,
                ]);

            return;
        }

        $kind = $reading->risk === 'critical' ? 'vital_critical' : 'vital_warning';
        $payload = VitalAlertPayload::forReading($reading);

        // Avoid duplicate open alerts for the same vital within 30 minutes.
        $recentDuplicate = AppNotification::where('user_id', $patient->id)
            ->where('kind', $kind)
            ->where('resolved', false)
            ->where('created_at', '>=', now()->subMinutes(30))
            ->where('action_arguments->vital_key', $reading->vital_key)
            ->exists();

        if ($recentDuplicate) {
            return;
        }

        $notification = AppNotification::create([
            'user_id' => $patient->id,
            'kind' => $kind,
            'title' => $payload['title'],
            'body' => $payload['body'],
            'action_route' => '/patient/vitals',
            'action_arguments' => [
                'vital_key' => $reading->vital_key,
                'reading_id' => (string) $reading->id,
                'value' => $reading->value,
                'secondary_value' => $reading->secondary_value,
                'risk' => $reading->risk,
            ],
            'read' => false,
            'resolved' => false,
        ]);

        VitalAlertBroadcast::dispatch($patient, $reading, $notification);
    }
}
