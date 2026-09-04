<?php

namespace App\Services;

use App\Events\RealtimeDataChanged;
use App\Models\Announcement;
use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\AssistantPermission;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\ChatMessage;
use App\Models\ClinicalReport;
use App\Models\Conversation;
use App\Models\EmergencyContact;
use App\Models\ExternalAccessToken;
use App\Models\MealPlan;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Models\PatientAssignedVital;
use App\Models\PatientHealthProfile;
use App\Models\PatientReportRequest;
use App\Models\PatientTrackedVital;
use App\Models\RealtimeEvent;
use App\Models\SosEvent;
use App\Models\SosResponseAction;
use App\Models\SupportTicket;
use App\Models\SupportTicketReply;
use App\Models\SystemSetting;
use App\Models\User;
use App\Models\UserInvite;
use App\Models\UserSetting;
use App\Models\VitalCatalog;
use App\Models\VitalRangeOverride;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use Closure;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Resolves model changes to private channels and client data domains.
 *
 * Signals are deliberately ephemeral. Nothing in this service writes an
 * alert, counter, dashboard total, notification state, or event payload to
 * application tables.
 */
class RealtimeSignalService
{
    /** Nested guard used while installing a database snapshot. */
    private static int $muteDepth = 0;

    /** @return list<class-string<Model>> */
    public static function observedModels(): array
    {
        return [
            Announcement::class,
            AppNotification::class,
            Appointment::class,
            AssistantPermission::class,
            AuditEntry::class,
            CareAssignment::class,
            CareProvider::class,
            CareRequest::class,
            ChatMessage::class,
            ClinicalReport::class,
            Conversation::class,
            EmergencyContact::class,
            ExternalAccessToken::class,
            MealPlan::class,
            MedicalDocument::class,
            Medication::class,
            MedicationDose::class,
            PatientAssignedVital::class,
            PatientHealthProfile::class,
            PatientReportRequest::class,
            PatientTrackedVital::class,
            SosEvent::class,
            SosResponseAction::class,
            SupportTicket::class,
            SupportTicketReply::class,
            SystemSetting::class,
            User::class,
            UserInvite::class,
            UserSetting::class,
            VitalCatalog::class,
            VitalRangeOverride::class,
            VitalReading::class,
            VitalReportRequest::class,
        ];
    }

    /**
     * True while a snapshot install has asked for silence. Nothing at all is
     * signalled — neither the socket nor the buffer clients read from.
     */
    public static function muted(): bool
    {
        return self::$muteDepth > 0;
    }

    public static function enabled(): bool
    {
        if (self::$muteDepth > 0) {
            return false;
        }

        $driver = (string) config('broadcasting.default');
        if (! in_array($driver, ['reverb', 'pusher', 'ably', 'redis'], true)) {
            return false;
        }

        $connection = config("broadcasting.connections.{$driver}", []);
        if (! is_array($connection) || $connection === []) {
            return false;
        }

        if (in_array($driver, ['reverb', 'pusher'], true)) {
            return filled($connection['key'] ?? null)
                && filled($connection['secret'] ?? null)
                && filled($connection['app_id'] ?? null);
        }

        if ($driver === 'ably') {
            return filled($connection['key'] ?? null);
        }

        return ($connection['driver'] ?? null) === 'redis';
    }

    /**
     * Install a seed/import snapshot without enqueueing one broadcast job per
     * row. Runtime simulations and normal application writes remain observed.
     */
    public static function withoutSignals(Closure $callback): mixed
    {
        self::$muteDepth++;

        try {
            return $callback();
        } finally {
            self::$muteDepth--;
        }
    }

    /**
     * @param  list<string>  $channels
     * @param  list<string>  $domains
     */
    public static function signal(
        array $channels,
        array $domains,
        string $action,
        string $resourceType,
        string|int|null $resourceId = null,
    ): void {
        if (self::muted() || $channels === [] || $domains === []) {
            return;
        }

        $channels = array_values(array_unique($channels));
        $domains = array_values(array_unique($domains));

        // The buffer is written first and unconditionally. It is what makes a
        // change reach a client that has no socket — no Reverb server, no
        // queue worker, a phone that just came back from the lock screen — in
        // seconds rather than at the next full poll. When the socket is up it
        // arrives there first and this row is simply never read.
        self::record($channels, $domains, $action, $resourceType, $resourceId);

        if (! self::enabled()) {
            return;
        }

        // A broadcast now goes out inline (see [RealtimeDataChanged]), so a
        // socket server that is down or slow must not be able to fail the
        // write that triggered it. The buffer above already guarantees
        // delivery; the socket is the fast path, not the only one.
        try {
            RealtimeDataChanged::dispatch(
                $channels,
                $domains,
                $action,
                $resourceType,
                $resourceId,
            );
        } catch (Throwable $e) {
            Log::warning('Realtime broadcast failed; clients fall back to the change buffer.', [
                'resource_type' => $resourceType,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Appends one row per channel to the short-lived change buffer.
     *
     * @param  list<string>  $channels
     * @param  list<string>  $domains
     */
    private static function record(
        array $channels,
        array $domains,
        string $action,
        string $resourceType,
        string|int|null $resourceId,
    ): void {
        $now = now();
        $domainList = implode(',', $domains);

        try {
            RealtimeEvent::insert(array_map(static fn (string $channel) => [
                'channel' => $channel,
                'domains' => $domainList,
                'action' => $action,
                'resource_type' => $resourceType,
                'resource_id' => $resourceId === null ? null : (string) $resourceId,
                'created_at' => $now,
            ], $channels));
        } catch (Throwable $e) {
            // A missing table (mid-deploy) or a locked database must never
            // turn a successful clinical write into a failed request.
            Log::warning('Realtime change buffer write failed.', [
                'resource_type' => $resourceType,
                'error' => $e->getMessage(),
            ]);

            return;
        }

        self::pruneOccasionally();
    }

    /**
     * Keeps the buffer to its retention window without a scheduler.
     *
     * The sweep is cheap and rare — roughly one write in fifty — so the table
     * stays a few minutes deep whether or not anything else runs on the box.
     */
    private static function pruneOccasionally(): void
    {
        if (random_int(1, 50) !== 1) {
            return;
        }

        try {
            RealtimeEvent::where(
                'created_at',
                '<',
                now()->subMinutes(RealtimeEvent::RETENTION_MINUTES),
            )->delete();
        } catch (Throwable) {
            // Retention is housekeeping; never surface it to a caller.
        }
    }

    /**
     * The channels one signed-in user listens on.
     *
     * The socket client subscribes to exactly these, and the fallback cursor
     * endpoint reads exactly these, so a change cannot arrive over one path
     * and be invisible on the other. Note what is *not* here: a doctor has no
     * per-patient channel to subscribe to, because [patientChannels] already
     * addresses every assigned doctor's own user channel.
     *
     * @return list<string>
     */
    public static function channelsForUser(User $user): array
    {
        return array_values(array_filter([
            'user.'.$user->id,
            'app',
            in_array($user->role, ['admin', 'mcare_assistant'], true) ? 'staff' : null,
        ]));
    }

    /** @param  list<string>|null  $domains */
    public static function forModel(Model $model, string $action, ?array $domains = null): void
    {
        if (self::muted()) {
            return;
        }

        self::signal(
            self::channelsFor($model),
            $domains ?? self::domainsFor($model),
            $action,
            class_basename($model),
            $model->getKey(),
        );
    }

    /** @return list<string> */
    private static function channelsFor(Model $model): array
    {
        if ($model instanceof Announcement) {
            // Patients now read announcements on their home feed, so one
            // addressed to them has to reach every client, not just the
            // console that wrote it.
            return in_array($model->audience, ['all', 'patients'], true)
                ? ['app', 'staff']
                : ['staff'];
        }

        if ($model instanceof VitalCatalog || $model instanceof CareProvider) {
            return ['app', 'staff'];
        }

        if ($model instanceof SystemSetting || $model instanceof AuditEntry) {
            return ['staff'];
        }

        if ($model instanceof User) {
            return ['user.'.$model->id, 'staff'];
        }

        if ($model instanceof AssistantPermission) {
            return ['user.'.$model->user_id, 'staff'];
        }

        if ($model instanceof UserInvite) {
            return ['user.'.$model->user_id, 'staff'];
        }

        if ($model instanceof Conversation) {
            return self::userChannels([$model->user_id, $model->participant_user_id]);
        }

        if ($model instanceof Appointment) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->user_id),
                ...self::userChannels([$model->doctor_user_id]),
            ]));
        }

        if ($model instanceof Medication) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->user_id),
                ...self::userChannels([$model->prescribed_by_user_id]),
            ]));
        }

        if ($model instanceof MedicalDocument) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->user_id),
                ...self::userChannels([$model->shared_with_doctor_id]),
            ]));
        }

        if ($model instanceof ChatMessage) {
            $conversation = $model->relationLoaded('conversation')
                ? $model->conversation
                : $model->conversation()->first();

            return $conversation
                ? self::userChannels([$conversation->user_id, $conversation->participant_user_id])
                : [];
        }

        if ($model instanceof SupportTicket) {
            return array_values(array_unique([
                ...self::userChannels([$model->user_id, $model->assigned_to]),
                'staff',
            ]));
        }

        if ($model instanceof SupportTicketReply) {
            $ticket = $model->relationLoaded('ticket')
                ? $model->ticket
                : $model->ticket()->first();

            return $ticket ? self::channelsFor($ticket) : [];
        }

        if ($model instanceof CareAssignment) {
            $providerUserId = CareProvider::whereKey($model->provider_id)->value('user_id');

            return array_values(array_unique([
                ...self::patientChannels((int) $model->patient_user_id),
                ...self::userChannels([$providerUserId]),
            ]));
        }

        if ($model instanceof CareRequest) {
            $providerUserIds = CareProvider::query()
                ->whereIn('id', array_filter([$model->provider_id, $model->assigned_provider_id]))
                ->pluck('user_id')
                ->all();

            return array_values(array_unique([
                ...self::patientChannels((int) $model->user_id),
                ...self::userChannels($providerUserIds),
            ]));
        }

        if ($model instanceof PatientReportRequest) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->patient_user_id),
                ...self::userChannels([$model->requested_by_user_id, $model->doctor_user_id]),
            ]));
        }

        if ($model instanceof ClinicalReport) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->patient_user_id),
                ...self::userChannels([$model->author_user_id]),
            ]));
        }

        if ($model instanceof MealPlan) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->patient_user_id),
                ...self::userChannels([$model->assigned_by_user_id]),
            ]));
        }

        if ($model instanceof ExternalAccessToken) {
            return array_values(array_unique([
                ...self::patientChannels((int) $model->patient_user_id),
                'external.'.$model->id,
            ]));
        }

        if ($model instanceof SosResponseAction) {
            $event = $model->relationLoaded('event')
                ? $model->event
                : $model->event()->first();

            return $event
                ? array_values(array_unique([
                    ...self::patientChannels((int) $event->user_id),
                    ...self::userChannels([$model->user_id]),
                ]))
                : self::userChannels([$model->user_id]);
        }

        $patientId = $model->getAttribute('user_id');
        if ($patientId !== null) {
            return self::patientChannels((int) $patientId);
        }

        return [];
    }

    /** @return list<string> */
    private static function patientChannels(int $patientId): array
    {
        if ($patientId <= 0) {
            return ['staff'];
        }

        $doctorUserIds = CareAssignment::query()
            ->where('patient_user_id', $patientId)
            ->whereNull('ended_at')
            ->join('care_providers', 'care_providers.id', '=', 'care_assignments.provider_id')
            ->whereNotNull('care_providers.user_id')
            ->pluck('care_providers.user_id')
            ->all();

        return array_values(array_unique([
            'user.'.$patientId,
            ...self::userChannels($doctorUserIds),
            ...ExternalAccessToken::query()
                ->where('patient_user_id', $patientId)
                ->whereNull('revoked_at')
                ->where('expires_at', '>', now())
                ->pluck('id')
                ->map(fn ($id) => 'external.'.$id)
                ->all(),
            'staff',
        ]));
    }

    /** @param  array<int, int|string|null>  $userIds
     * @return list<string>
     */
    private static function userChannels(array $userIds): array
    {
        return collect($userIds)
            ->filter(fn ($id) => $id !== null && (int) $id > 0)
            ->map(fn ($id) => 'user.'.(int) $id)
            ->unique()
            ->values()
            ->all();
    }

    /** @return list<string> */
    private static function domainsFor(Model $model): array
    {
        return match (true) {
            $model instanceof User,
            $model instanceof PatientHealthProfile,
            $model instanceof EmergencyContact => ['profile'],

            $model instanceof AssistantPermission => ['permissions', 'profile'],
            $model instanceof UserInvite => ['approvals', 'profile'],

            $model instanceof VitalReading,
            $model instanceof VitalRangeOverride,
            $model instanceof PatientAssignedVital,
            $model instanceof PatientTrackedVital,
            $model instanceof VitalCatalog => ['vitals', 'alerts'],

            $model instanceof Medication,
            $model instanceof MedicationDose => ['medications'],

            $model instanceof Appointment => ['appointments'],
            $model instanceof MedicalDocument => ['documents'],
            $model instanceof Conversation,
            $model instanceof ChatMessage => ['messages'],

            // A closure notice is alert traffic too: it is the signal that
            // tells a patient's open alert card to stop being an open alert.
            $model instanceof AppNotification => in_array(
                $model->kind,
                [...AlertResolutionNotifier::KINDS, 'alert_resolved', 'sos_resolved'],
                true,
            ) ? ['notifications', 'alerts'] : ['notifications'],

            $model instanceof SupportTicket,
            $model instanceof SupportTicketReply => ['support'],

            $model instanceof SosEvent,
            $model instanceof SosResponseAction => ['sos', 'alerts'],
            $model instanceof CareProvider,
            $model instanceof CareRequest,
            $model instanceof CareAssignment,
            $model instanceof MealPlan => ['care'],

            $model instanceof VitalReportRequest,
            $model instanceof ClinicalReport,
            $model instanceof PatientReportRequest => ['reports'],

            $model instanceof Announcement => ['announcements'],
            $model instanceof SystemSetting,
            $model instanceof UserSetting => ['settings'],
            $model instanceof AuditEntry => ['audit'],
            $model instanceof ExternalAccessToken => ['external_access'],
            default => ['session'],
        };
    }
}
