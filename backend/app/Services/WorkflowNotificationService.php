<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareRequest;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\SupportTicket;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Durable, cross-role workflow notifications.
 *
 * Reverb invalidates live screens, but it is intentionally ephemeral and a
 * suspended phone cannot hear it. These records are the durable counterpart:
 * they drive the in-app inbox and the central FCM observer without placing
 * message, support, or clinical content in the push payload itself.
 */
final class WorkflowNotificationService
{
    public static function messageSent(
        ChatMessage $message,
        Conversation $conversation,
        User $sender,
    ): ?AppNotification {
        $recipientId = (int) $conversation->user_id === (int) $sender->id
            ? $conversation->participant_user_id
            : $conversation->user_id;

        if ($recipientId === null || (int) $recipientId === (int) $sender->id) {
            return null;
        }

        $recipient = User::query()->find($recipientId);
        if ($recipient === null) {
            return null;
        }

        return self::create(
            $recipient,
            'message',
            'New message from '.$sender->fullName(),
            'Open mCare to read and reply securely.',
            self::routeFor($recipient, 'messages'),
            [
                'conversation_id' => (string) $conversation->id,
                'message_id' => (string) $message->id,
            ],
        );
    }

    /** Mark the durable message notices together with the conversation. */
    public static function markConversationRead(User $viewer, Conversation $conversation): void
    {
        $updated = AppNotification::query()
            ->where('user_id', $viewer->id)
            ->where('kind', 'message')
            ->where('read', false)
            ->where('action_arguments->conversation_id', (string) $conversation->id)
            ->update(['read' => true]);

        if ($updated > 0) {
            RealtimeSignalService::signal(
                ['user.'.$viewer->id],
                ['messages', 'notifications'],
                'updated',
                'AppNotification',
            );
        }
    }

    public static function careRequestOpened(CareRequest $careRequest, User $patient): void
    {
        self::operationsRecipients('can_manage_care_requests')
            ->each(function (User $recipient) use ($careRequest, $patient): void {
                self::create(
                    $recipient,
                    'care_request',
                    'New care request',
                    $patient->fullName().' requested '.$careRequest->provider_name.'.',
                    self::routeFor($recipient, 'care_requests'),
                    [
                        'patient_id' => (string) $patient->id,
                        'care_request_id' => (string) $careRequest->id,
                    ],
                );
            });
    }

    public static function supportTicketOpened(SupportTicket $ticket, User $patient): void
    {
        self::operationsRecipients()
            ->each(function (User $recipient) use ($ticket, $patient): void {
                self::create(
                    $recipient,
                    'support',
                    'New support request',
                    $patient->fullName().' opened a '.$ticket->priority.' priority ticket.',
                    self::routeFor($recipient, 'support'),
                    [
                        'patient_id' => (string) $patient->id,
                        'ticket_id' => (string) $ticket->id,
                    ],
                );
            });
    }

    public static function patientRepliedToSupport(SupportTicket $ticket, User $patient): void
    {
        $recipients = $ticket->assigned_to
            ? User::query()->whereKey($ticket->assigned_to)->get()
            : self::operationsRecipients()->get();

        $recipients->each(function (User $recipient) use ($ticket, $patient): void {
            self::create(
                $recipient,
                'support',
                'New support reply',
                $patient->fullName().' replied to a support request.',
                self::routeFor($recipient, 'support'),
                [
                    'patient_id' => (string) $patient->id,
                    'ticket_id' => (string) $ticket->id,
                ],
            );
        });
    }

    public static function staffRepliedToSupport(SupportTicket $ticket, User $staff): void
    {
        $patient = $ticket->user()->first();
        if ($patient === null) {
            return;
        }

        self::create(
            $patient,
            'support',
            'Support replied',
            $staff->fullName().' replied to your support request.',
            self::routeFor($patient, 'support'),
            ['ticket_id' => (string) $ticket->id],
        );
    }

    public static function supportStatusChanged(SupportTicket $ticket, string $status): void
    {
        $patient = $ticket->user()->first();
        if ($patient === null) {
            return;
        }

        $label = match ($status) {
            'resolved' => 'resolved',
            'closed' => 'closed',
            'open' => 'reopened',
            default => 'updated',
        };

        self::create(
            $patient,
            'support',
            'Support request '.$label,
            'Open mCare to review the latest support update.',
            self::routeFor($patient, 'support'),
            ['ticket_id' => (string) $ticket->id, 'status' => $status],
        );
    }

    /** Notify the other participant after an appointment write. */
    public static function appointmentChanged(
        Appointment $appointment,
        User $actor,
        string $change,
    ): ?AppNotification {
        $recipientId = (int) $actor->id === (int) $appointment->user_id
            ? $appointment->doctor_user_id
            : $appointment->user_id;
        if ($recipientId === null || (int) $recipientId === (int) $actor->id) {
            return null;
        }

        $recipient = User::query()->find($recipientId);
        if ($recipient === null) {
            return null;
        }

        $title = match ($change) {
            'created' => (int) $actor->id === (int) $appointment->user_id
                ? 'New appointment request'
                : 'New appointment',
            'cancelled' => 'Appointment cancelled',
            default => 'Appointment updated',
        };

        return self::create(
            $recipient,
            'appointment',
            $title,
            $actor->fullName().' updated the appointment for '
                .$appointment->scheduled_at->toDayDateTimeString().'.',
            self::routeFor($recipient, 'appointments'),
            ['appointment_id' => (string) $appointment->id],
        );
    }

    private static function create(
        User $recipient,
        string $kind,
        string $title,
        string $body,
        ?string $route,
        array $arguments = [],
    ): AppNotification {
        return AppNotification::create([
            'user_id' => $recipient->id,
            'kind' => $kind,
            'title' => $title,
            'body' => $body,
            'action_route' => $route,
            'action_arguments' => $arguments === [] ? null : $arguments,
            'read' => false,
            'resolved' => false,
        ]);
    }

    private static function operationsRecipients(?string $permission = null): Builder
    {
        return User::query()
            ->where('approval_status', 'active')
            ->where(function (Builder $query) use ($permission): void {
                $query->where('role', 'admin')
                    ->orWhere(function (Builder $assistant) use ($permission): void {
                        $assistant->where('role', 'mcare_assistant');
                        if ($permission !== null) {
                            $assistant->whereHas(
                                'assistantPermissions',
                                fn (Builder $grant) => $grant->where('permission_key', $permission),
                            );
                        }
                    });
            });
    }

    private static function routeFor(User $user, string $workflow): ?string
    {
        return match ($workflow) {
            'messages' => match ($user->role) {
                'patient' => '/patient/messages',
                'doctor' => '/doctor/messages',
                'admin' => '/admin/messages',
                'mcare_assistant' => '/assistant/messages',
                default => null,
            },
            'support' => match ($user->role) {
                'patient' => '/patient/support',
                'admin' => '/admin/support',
                'mcare_assistant' => '/assistant/support',
                default => null,
            },
            'care_requests' => match ($user->role) {
                'admin' => '/admin/care-requests',
                'mcare_assistant' => '/assistant/care-requests',
                default => null,
            },
            'appointments' => match ($user->role) {
                'patient' => '/patient/appointments',
                'doctor' => '/doctor/appointments',
                default => null,
            },
            default => null,
        };
    }
}
