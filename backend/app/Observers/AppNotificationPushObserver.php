<?php

namespace App\Observers;

use App\Models\AppNotification;
use App\Services\FcmPushService;

/**
 * Makes every persisted inbox notification eligible for immediate push.
 * Emergency and resolution workflows keep their specialized dispatchers,
 * which carry responder/event context and must not be duplicated here.
 */
class AppNotificationPushObserver
{
    private const SPECIALIZED_KINDS = [
        'sos',
        'sos_resolved',
        'alert_resolved',
    ];

    public function created(AppNotification $notification): void
    {
        if (in_array($notification->kind, self::SPECIALIZED_KINDS, true)) {
            return;
        }

        $arguments = is_array($notification->action_arguments)
            ? $notification->action_arguments
            : [];
        $data = [
            'kind' => $notification->kind,
            'notification_id' => (string) $notification->id,
        ];
        foreach ([
            'patient_id',
            'event_id',
            'alert_id',
            'appointment_id',
            'conversation_id',
            'status',
        ] as $key) {
            if (isset($arguments[$key]) && is_scalar($arguments[$key])) {
                $data[$key] = (string) $arguments[$key];
            }
        }

        FcmPushService::sendToUsers(
            [(int) $notification->user_id],
            (string) $notification->title,
            (string) $notification->body,
            $data,
            priority: in_array(
                $notification->kind,
                ['vital_warning', 'vital_critical', 'alert'],
                true,
            ) ? 'high' : 'normal',
        );
    }
}
