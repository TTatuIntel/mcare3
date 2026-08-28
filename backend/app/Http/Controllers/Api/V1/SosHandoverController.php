<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\SosEvent;
use App\Models\SosResponseAction;
use App\Services\FcmPushService;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use App\Support\SosRoles;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Hand a live emergency to a provider.
 *
 * This used to run through the admin assignment CRUD, which is the wrong
 * shape for an emergency in two ways. It refuses a provider who is already
 * assigned — so handing over to the patient's own care team, the first and
 * most clinically correct choice the handover sheet offers, could never
 * succeed. And a `care_assignments` row on its own tells the receiving
 * provider nothing: it is a scheduling fact, not a summons. They learnt of
 * the emergency whenever their caseload next happened to refresh.
 *
 * So a handover here is one atomic act: the provider is on the care team
 * (reused, not duplicated), the emergency is stamped as theirs, the trail
 * records it, and they are notified — in-app, by push, and by a real-time
 * signal on their own channel so the SOS lands on their screen now rather
 * than at the next poll.
 */
class SosHandoverController extends Controller
{
    use ApiResponse;

    public function store(Request $request, SosEvent $event)
    {
        $actor = $request->user();
        abort_unless(
            SosRoles::isCoordinator($actor),
            403,
            'Only a coordinator can re-route an emergency.'
        );

        // A closed emergency has nobody left to hand it to.
        abort_if(
            ! in_array($event->status, ['active', 'acknowledged'], true),
            409,
            'This emergency is already closed.'
        );

        $data = $request->validate([
            'provider_id' => 'required|exists:care_providers,id',
            'detail' => 'nullable|string|max:300',
        ]);

        $provider = CareProvider::with('user')->findOrFail($data['provider_id']);
        $providerLabel = $provider->name ?? $provider->user?->fullName() ?? 'Provider';

        [$assignment, $action, $reused] = DB::transaction(function () use (
            $event, $provider, $data, $actor, $providerLabel
        ) {
            // Reuse rather than refuse. A care-team member is already bound to
            // this patient; that is precisely why they are offered first.
            $assignment = CareAssignment::query()
                ->where('patient_user_id', $event->user_id)
                ->where('provider_id', $provider->id)
                ->whereNull('ended_at')
                ->first();

            $reused = $assignment !== null;

            $assignment ??= CareAssignment::create([
                'patient_user_id' => $event->user_id,
                'provider_id' => $provider->id,
                'role' => 'Primary',
                'assigned_at' => now(),
                'assigned_reason' => trim((string) ($data['detail'] ?? '')) ?: 'Emergency handover',
                'assigned_by' => $actor->id,
            ]);

            $action = SosResponseAction::create([
                'sos_event_id' => $event->id,
                'user_id' => $actor->id,
                'actor_name' => SosRoles::actorName($actor),
                'action' => 'assigned_provider',
                'detail' => trim((string) ($data['detail'] ?? '')) ?: $providerLabel,
            ]);

            // The emergency now has a named owner. Leaving it "active" after a
            // handover is what let two coordinators work the same event while
            // each believed the other had not started.
            $event->update([
                'status' => 'acknowledged',
                'responded_by' => $providerLabel,
                'responded_at' => now(),
            ]);

            return [$assignment, $action, $reused];
        });

        $this->notifyProvider($event, $provider, $providerLabel, $actor);

        AuditEntry::create([
            'actor_user_id' => $actor->id,
            'actor_label' => SosRoles::actorName($actor),
            'action' => 'Handed over SOS',
            'target' => ($event->user?->fullName() ?? 'Patient').' → '.$providerLabel,
            'category' => 'sos',
            'happened_at' => now(),
        ]);

        return $this->success(
            [
                'event' => $event->fresh()->load('responseActions.user')->toApiArray(),
                'action' => $action->toApiArray(),
                'assignment_id' => (string) $assignment->id,
                'already_on_care_team' => $reused,
            ],
            $providerLabel.' now has this emergency.',
            201,
        );
    }

    /**
     * Reach the person taking over, by every route we have. The in-app
     * notification and the care-assignment row both broadcast on their own
     * (see RealtimeModelObserver); the explicit signal adds the `sos` domain,
     * which is what puts the event itself on their emergency screen without
     * waiting for the fallback poll.
     */
    private function notifyProvider(
        SosEvent $event,
        CareProvider $provider,
        string $providerLabel,
        $actor,
    ): void {
        $providerUserId = $provider->user_id;
        if ($providerUserId === null) {
            return;
        }

        $patient = $event->user;
        $patientName = $patient?->fullName() ?? 'a patient';
        $body = trim(sprintf(
            '%s handed you %s — %s%s',
            SosRoles::actorName($actor),
            $patientName,
            SosEvent::kindLabel($event->kind),
            $event->location_label ? ' · '.$event->location_label : '',
        ));

        AppNotification::create([
            'user_id' => $providerUserId,
            'kind' => 'sos',
            'title' => 'Emergency handed to you',
            'body' => $body,
            'action_route' => '/doctor/sos',
            'action_arguments' => [
                'patient_id' => (string) $event->user_id,
                'event_id' => (string) $event->id,
            ],
            'read' => false,
            'resolved' => false,
        ]);

        FcmPushService::sendToUsers(
            [(int) $providerUserId],
            'Emergency handed to you',
            $body,
            [
                'kind' => 'sos',
                'event_id' => (string) $event->id,
                'patient_id' => (string) $event->user_id,
                'patient_name' => $patientName,
            ],
        );

        RealtimeSignalService::signal(
            ['user.'.$providerUserId, 'user.'.$event->user_id, 'staff'],
            ['sos', 'alerts', 'notifications', 'care'],
            'handover',
            'SosEvent',
            $event->id,
        );
    }
}
