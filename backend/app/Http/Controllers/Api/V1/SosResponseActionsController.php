<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\SosEvent;
use App\Models\SosResponseAction;
use App\Models\User;
use App\Support\ApiResponse;
use App\Support\SosRoles;
use Illuminate\Http\Request;

/**
 * The response trail for one emergency — what was tried, by whom, when.
 *
 * Shared by every responding role. Admins and mCare assistants coordinate
 * platform-wide; a doctor may only touch an emergency for a patient on their
 * own caseload, which is enforced here rather than left to the client.
 */
class SosResponseActionsController extends Controller
{
    use ApiResponse;

    public function index(Request $request, SosEvent $event)
    {
        $this->authorizeEvent($request->user(), $event);

        return $this->success([
            'actions' => $event->responseActions()
                ->with('user')
                ->orderBy('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function store(Request $request, SosEvent $event)
    {
        $user = $request->user();
        $this->authorizeEvent($user, $event);

        // A closed emergency is a closed record. Refusing the write here is
        // what stops a late click appending to something already reviewed.
        abort_if(
            ! in_array($event->status, ['active', 'acknowledged'], true),
            409,
            'This emergency is already closed.'
        );

        $data = $request->validate([
            'action' => 'required|string|in:'.implode(',', SosResponseAction::ACTIONS),
            'detail' => 'nullable|string|max:300',
        ]);

        $action = SosResponseAction::create([
            'sos_event_id' => $event->id,
            'user_id' => $user->id,
            'actor_name' => $this->actorName($user),
            'action' => $data['action'],
            'detail' => $data['detail'] ?? null,
        ]);

        return $this->success(
            ['action' => $action->toApiArray()],
            'Step recorded.',
            201
        );
    }

    private function actorName(User $user): string
    {
        return SosRoles::actorName($user);
    }

    /**
     * Doctors are scoped to their own caseload; coordinating roles are not.
     */
    private function authorizeEvent(User $user, SosEvent $event): void
    {
        if (SosRoles::isCoordinator($user)) {
            return;
        }

        abort_unless($user->role === 'doctor', 403, 'Not a responder.');

        $provider = CareProvider::where('user_id', $user->id)->first();
        abort_if($provider === null, 403, 'Not this patient’s emergency.');

        $assigned = CareAssignment::where('provider_id', $provider->id)
            ->where('patient_user_id', $event->user_id)
            ->whereNull('ended_at')
            ->exists();

        abort_unless($assigned, 403, 'Not this patient’s emergency.');
    }
}
