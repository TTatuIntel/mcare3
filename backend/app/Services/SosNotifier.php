<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\SosEvent;
use App\Models\User;

/**
 * Side-effects when an SOS event is triggered or resolved — creates
 * in-app notifications, audit entries, and FCM pushes.
 */
class SosNotifier
{
    public static function onTriggered(SosEvent $event): void
    {
        $patient = $event->user;
        $kindLabel = self::kindLabel($event->kind);
        $body = $event->note
            ? "{$kindLabel} — {$event->note}"
            : $kindLabel;
        if ($event->location_label) {
            $body .= ' · '.$event->location_label;
        }

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'sos',
            'title' => 'Emergency SOS activated',
            'body' => $body,
            'action_route' => '/patient/sos',
            'action_arguments' => ['event_id' => (string) $event->id],
            'read' => false,
            'resolved' => false,
        ]);

        AuditEntry::create([
            'actor_user_id' => $patient->id,
            'actor_label' => $patient->fullName(),
            'action' => 'Triggered SOS',
            'target' => $kindLabel,
            'category' => 'sos',
            'happened_at' => now(),
        ]);

        $recipients = FcmPushService::sosRecipientUserIds($patient->id);

        foreach ($recipients as $recipientId) {
            if ((int) $recipientId === (int) $patient->id) {
                continue;
            }
            $route = match (User::find($recipientId)?->role) {
                'doctor' => '/doctor/sos',
                'mcare_assistant' => '/assistant/sos',
                default => '/admin/sos',
            };
            AppNotification::create([
                'user_id' => $recipientId,
                'kind' => 'sos',
                'title' => 'SOS · '.$patient->fullName(),
                'body' => $body,
                'action_route' => $route,
                'action_arguments' => [
                    'patient_id' => (string) $patient->id,
                    'event_id' => (string) $event->id,
                ],
                'read' => false,
                'resolved' => false,
            ]);
        }

        FcmPushService::sendToUsers(
            $recipients,
            'SOS · '.$patient->fullName(),
            $body,
            [
                'kind' => 'sos',
                'event_id' => (string) $event->id,
                'patient_id' => (string) $patient->id,
                'patient_name' => $patient->fullName(),
            ],
        );
    }

    public static function onResolved(
        SosEvent $event,
        string $status,
        ?User $responder = null,
    ): void {
        $patient = $event->user;

        AppNotification::where('kind', 'sos')
            ->where('resolved', false)
            ->where(function ($q) use ($patient, $event) {
                $q->where('user_id', $patient->id)
                    ->orWhere('action_arguments->event_id', (string) $event->id);
            })
            ->update([
                'resolved' => true,
                'resolved_at' => now(),
                'read' => true,
            ]);

        if (! $responder) {
            return;
        }

        $label = $responder->role === 'doctor'
            ? 'Dr. '.$responder->fullName()
            : $responder->fullName();

        $title = match ($status) {
            'falseAlarm' => 'SOS marked as false alarm',
            'acknowledged' => 'Care team is responding',
            default => 'Your SOS was resolved',
        };

        $pushBody = "{$label} responded to your emergency alert.";

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'sos_resolved',
            'title' => $title,
            'body' => $pushBody,
            'action_route' => '/patient/sos',
            'read' => false,
        ]);

        FcmPushService::sendToUsers(
            [$patient->id],
            $title,
            $pushBody,
            [
                'kind' => 'sos_resolved',
                'event_id' => (string) $event->id,
                'status' => $status,
            ],
            priority: 'normal',
        );
    }

    private static function kindLabel(string $kind): string
    {
        return match ($kind) {
            'medical' => 'Medical emergency',
            'accident' => 'Accident',
            'fall' => 'Fall',
            'panic' => 'Panic',
            default => 'Emergency',
        };
    }
}
