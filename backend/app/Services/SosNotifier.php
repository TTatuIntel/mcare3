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

    /**
     * @param  bool  $notifyPatient  false when the caller is already telling
     *                               the patient in its own words — an alert
     *                               closed from the alert list speaks about
     *                               the alert the patient was shown, and two
     *                               messages about one emergency read as two
     *                               emergencies.
     */
    public static function onResolved(
        SosEvent $event,
        string $status,
        ?User $responder = null,
        bool $notifyPatient = true,
    ): void {
        $patient = $event->user;

        // Acknowledging is not an ending. The care team's copies stay open
        // until somebody actually closes the emergency, or a responder who
        // "acknowledged" and then got pulled away would silently take the
        // emergency off every other console.
        if ($status !== 'acknowledged') {
            self::suppressOpenAlertsFor($event, $status, $responder);
        }

        if (! $responder || ! $notifyPatient) {
            return;
        }

        $label = self::responderLabel($responder);
        $outcome = SosEvent::resolutionLabel($event->resolution);
        $note = trim((string) $event->resolution_note);

        $title = match ($status) {
            'falseAlarm' => 'SOS marked as false alarm',
            'acknowledged' => 'Care team is responding',
            default => 'Your SOS was resolved',
        };

        // The reason travels with the message. "Someone responded" leaves the
        // patient to guess whether anything was actually decided; the outcome
        // the responder picked is the whole point of having picked one.
        $pushBody = match ($status) {
            'acknowledged' => "{$label} is responding to your emergency alert.",
            default => "{$label} closed your emergency alert"
                .($outcome !== null ? " · {$outcome}" : '').'.',
        };
        if ($note !== '') {
            $pushBody .= ' '.$note;
        }

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'sos_resolved',
            'title' => $title,
            'body' => $pushBody,
            'action_route' => '/patient/sos',
            'action_arguments' => array_filter([
                'event_id' => (string) $event->id,
                'status' => $status,
                'resolution' => $event->resolution,
                'resolution_note' => $note !== '' ? $note : null,
                'resolved_by' => $label,
            ], fn ($v) => $v !== null),
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

    /**
     * Take this emergency off every console it is sitting on.
     *
     * Scoped to the event, not to the patient: a patient can have a second
     * emergency open, and closing the first one must never clear an alert
     * nobody has looked at yet. The patient's own copy carries the same
     * event id, so it is cleared by the same pass.
     */
    private static function suppressOpenAlertsFor(
        SosEvent $event,
        string $status,
        ?User $responder,
    ): void {
        $closure = array_filter([
            'closed_status' => $status,
            'resolution' => $event->resolution,
            'resolution_note' => $event->resolution_note,
            'resolved_by' => $responder ? self::responderLabel($responder) : 'Patient',
            'resolved_by_user_id' => $responder?->id,
        ], fn ($v) => $v !== null);

        $open = AppNotification::query()
            ->where('kind', 'sos')
            ->where('resolved', false)
            ->where('action_arguments->event_id', (string) $event->id)
            ->get();

        foreach ($open as $notification) {
            $args = is_array($notification->action_arguments)
                ? $notification->action_arguments
                : [];

            // One row at a time so the realtime observer fires for each: a
            // mass update clears the database but leaves the emergency on
            // every open console until that client happens to poll again.
            $notification->update([
                'resolved' => true,
                'resolved_at' => now(),
                'read' => true,
                'action_arguments' => array_merge($args, $closure),
            ]);
        }
    }

    /** How a responder is named to the patient they answered. */
    private static function responderLabel(User $responder): string
    {
        return AlertResolutionNotifier::responderLabel($responder);
    }

    private static function kindLabel(string $kind): string
    {
        return SosEvent::kindLabel($kind);
    }
}
