<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\SosEvent;
use App\Models\User;
use App\Support\VitalLabels;

/**
 * Closing a clinical alert, as one act with consequences.
 *
 * A responder pressing "resolve" used to do one thing: flip two booleans on
 * the patient's notification row. The reason they typed was filed where only
 * another clinician would ever look, the patient — whose reading it was, and
 * who watched the red card sit on their home screen — was told nothing at
 * all, and a duplicate alert about the same vital stayed open for the next
 * person to work a second time.
 *
 * Ending an alert is a conversation, not a flag: the outcome is recorded
 * against the alert, every open alert about the same thing is closed with
 * that same outcome so nobody chases it twice, an emergency behind the alert
 * is closed with it, and the patient is told who acted and what they decided.
 */
class AlertResolutionNotifier
{
    /** What a responder can say they did. Mirrored by AlertResolutionAction. */
    public const ACTIONS = [
        'patient_contacted',
        'medication_adjusted',
        'follow_up_scheduled',
        'monitored',
        'referred',
        'reading_error',
        'other',
    ];

    /** Alert kinds that carry a clinical outcome. */
    public const KINDS = ['vital_warning', 'vital_critical', 'sos'];

    public static function actionLabel(string $action, ?string $custom = null): string
    {
        if ($action === 'other') {
            $custom = trim((string) $custom);

            return $custom !== '' ? $custom : 'Other action';
        }

        return match ($action) {
            'patient_contacted' => 'Patient contacted',
            'medication_adjusted' => 'Medication adjusted',
            'follow_up_scheduled' => 'Follow-up scheduled',
            'monitored' => 'Monitored / observed',
            'referred' => 'Referred to care',
            'reading_error' => 'Reading error / false alarm',
            default => 'Reviewed',
        };
    }

    /** How a responder signs what they did, in the words a patient reads. */
    public static function responderLabel(User $responder): string
    {
        return match ($responder->role) {
            'doctor' => 'Dr. '.$responder->fullName(),
            'admin' => $responder->fullName().' (Care admin)',
            'mcare_assistant' => $responder->fullName().' (Care team)',
            default => $responder->fullName(),
        };
    }

    /**
     * Someone has picked this up, but has not finished it.
     *
     * Recorded so a second responder opening the same alert can see it is
     * already being worked rather than calling the same patient again.
     */
    public static function acknowledge(AppNotification $alert, User $responder): AppNotification
    {
        $args = is_array($alert->action_arguments) ? $alert->action_arguments : [];
        $args['acknowledged_by'] = self::responderLabel($responder);
        $args['acknowledged_by_user_id'] = (int) $responder->id;
        $args['acknowledged_at'] = now()->toIso8601String();

        $alert->update(['read' => true, 'action_arguments' => $args]);

        return $alert->fresh();
    }

    /**
     * Close an alert with the outcome the responder chose.
     *
     * @return AppNotification the closed alert, reloaded
     */
    public static function resolve(
        AppNotification $alert,
        User $responder,
        string $action,
        ?string $customAction,
        string $note,
    ): AppNotification {
        $args = is_array($alert->action_arguments) ? $alert->action_arguments : [];
        $args['resolution_action'] = $action;
        $args['resolution_note'] = $note;
        if ($action === 'other' && trim((string) $customAction) !== '') {
            $args['resolution_custom_action'] = trim((string) $customAction);
        }
        // Who ended it, kept on the alert itself: the audit log answers this
        // for a reviewer, but the person waiting on the answer is the patient,
        // and every list that shows a closed alert has to name the responder
        // without a second lookup.
        $args['resolved_by'] = self::responderLabel($responder);
        $args['resolved_by_user_id'] = (int) $responder->id;
        $args['resolved_by_role'] = $responder->role;

        $alert->update([
            'read' => true,
            'resolved' => true,
            'resolved_at' => now(),
            'action_arguments' => $args,
        ]);

        $alert = $alert->fresh();

        self::suppressDuplicates($alert, [
            'resolution_action' => $args['resolution_action'],
            'resolution_note' => $args['resolution_note'],
            'resolution_custom_action' => $args['resolution_custom_action'] ?? null,
            'resolved_by' => $args['resolved_by'],
            'resolved_by_user_id' => $args['resolved_by_user_id'],
            'resolved_by_role' => $args['resolved_by_role'],
        ]);
        self::closeLinkedEmergency($alert, $responder, $action, $customAction, $note);
        self::tellPatient($alert, $responder, $action, $customAction, $note);

        return $alert;
    }

    /**
     * Every other open alert about the same thing, closed with the same words.
     *
     * One dangerous reading can raise several alerts — a repeated measurement,
     * a warning that became a critical, an emergency raised beside it. A
     * responder who has dealt with the patient has dealt with all of them, so
     * leaving the rest open only sends the next clinician after a problem
     * somebody already handled.
     */
    private static function suppressDuplicates(AppNotification $alert, array $resolution): void
    {
        $args = is_array($alert->action_arguments) ? $alert->action_arguments : [];
        $vitalKey = $args['vital_key'] ?? null;
        $eventId = $args['event_id'] ?? null;

        if ($vitalKey === null && $eventId === null) {
            return;
        }

        $resolution = array_filter($resolution, fn ($v) => $v !== null);

        $siblings = AppNotification::query()
            ->where('user_id', $alert->user_id)
            ->whereIn('kind', self::KINDS)
            ->where('resolved', false)
            ->where('id', '!=', $alert->id)
            ->where(function ($q) use ($vitalKey, $eventId) {
                if ($vitalKey !== null) {
                    $q->orWhere('action_arguments->vital_key', $vitalKey);
                }
                if ($eventId !== null) {
                    $q->orWhere('action_arguments->event_id', (string) $eventId);
                }
            })
            ->get();

        foreach ($siblings as $sibling) {
            $siblingArgs = is_array($sibling->action_arguments) ? $sibling->action_arguments : [];
            // Saved one at a time rather than in a mass update: a mass update
            // fires no model events, so every subscribed client would keep
            // showing these as open until its next full refresh.
            $sibling->update([
                'read' => true,
                'resolved' => true,
                'resolved_at' => now(),
                'action_arguments' => array_merge($siblingArgs, $resolution, [
                    'superseded_by_alert_id' => (string) $alert->id,
                ]),
            ]);
        }
    }

    /**
     * An alert raised by an emergency closes the emergency with it.
     *
     * The SOS console and the alert list are two windows onto the same event.
     * Clearing the alert card while the emergency stayed "active" left the
     * next responder looking at a live emergency nobody was working — and the
     * patient's own screen still showing an open SOS after being told it was
     * handled.
     */
    private static function closeLinkedEmergency(
        AppNotification $alert,
        User $responder,
        string $action,
        ?string $customAction,
        string $note,
    ): void {
        if ($alert->kind !== 'sos') {
            return;
        }

        $args = is_array($alert->action_arguments) ? $alert->action_arguments : [];
        $eventId = $args['event_id'] ?? null;
        if ($eventId === null) {
            return;
        }

        $event = SosEvent::find($eventId);
        if (! $event || ! in_array($event->status, ['active', 'acknowledged'], true)) {
            return;
        }

        // A reading error is the one outcome that says the emergency should
        // never have been raised; everything else is a real event that ended.
        $status = $action === 'reading_error' ? 'falseAlarm' : 'resolved';

        $event->update([
            'status' => $status,
            'resolution' => match ($action) {
                'patient_contacted' => 'patient_safe',
                'referred', 'medication_adjusted', 'monitored', 'follow_up_scheduled' => 'care_team_handling',
                default => 'other',
            },
            'resolution_note' => $action === 'other'
                ? trim(self::actionLabel($action, $customAction).' — '.$note)
                : $note,
            'responded_by' => self::responderLabel($responder),
            'responded_at' => now(),
        ]);

        // The emergency's own closure clears the care team's copies of it.
        // The patient hears once, from tellPatient(), in the words of the
        // alert they were actually shown.
        SosNotifier::onResolved($event->fresh(), $status, $responder, notifyPatient: false);
    }

    /**
     * The patient hears the outcome from the person who decided it.
     *
     * Without this the alert simply vanished from their screen: no reason, no
     * name, nothing to ask about at the next appointment. Silence after a
     * critical reading reads as being ignored.
     */
    private static function tellPatient(
        AppNotification $alert,
        User $responder,
        string $action,
        ?string $customAction,
        string $note,
    ): void {
        $who = self::responderLabel($responder);
        $what = self::actionLabel($action, $customAction);
        $subject = self::subjectLabel($alert);

        $title = $alert->kind === 'sos'
            ? 'Your emergency alert was closed'
            : ucfirst($subject).' alert resolved';

        $body = "{$who} reviewed your {$subject} alert · {$what}."
            .(trim($note) !== '' ? ' '.trim($note) : '');

        AppNotification::create([
            'user_id' => $alert->user_id,
            'kind' => 'alert_resolved',
            'title' => $title,
            'body' => $body,
            // Lands on the reading the alert was about, so the patient can see
            // the number the decision was made on.
            'action_route' => $alert->action_route ?? '/patient/vitals',
            'action_arguments' => array_filter([
                'alert_id' => (string) $alert->id,
                'vital_key' => is_array($alert->action_arguments)
                    ? ($alert->action_arguments['vital_key'] ?? null)
                    : null,
                'resolution_action' => $action,
                'resolution_note' => $note,
                'resolved_by' => $who,
            ], fn ($v) => $v !== null),
            'read' => false,
            'resolved' => false,
        ]);

        FcmPushService::sendToUsers(
            [$alert->user_id],
            $title,
            $body,
            [
                'kind' => 'alert_resolved',
                'alert_id' => (string) $alert->id,
                'patient_id' => (string) $alert->user_id,
            ],
            priority: 'normal',
        );
    }

    /** What the alert was about, in the patient's words. */
    private static function subjectLabel(AppNotification $alert): string
    {
        if ($alert->kind === 'sos') {
            return 'emergency';
        }

        $vitalKey = is_array($alert->action_arguments)
            ? ($alert->action_arguments['vital_key'] ?? null)
            : null;

        return $vitalKey ? strtolower(VitalLabels::label((string) $vitalKey)) : 'vital';
    }
}
