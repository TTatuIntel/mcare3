<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\SosEvent;
use App\Models\User;
use App\Support\ApiResponse;
use App\Support\SosRoles;
use Illuminate\Http\Request;

/**
 * Who can be handed this emergency, in the order a coordinator should try.
 *
 * The patient's own care team comes first: they already know the history, and
 * routing an emergency past them to a stranger is a clinical regression, not
 * a neutral choice. Only when nobody on the team is available does the list
 * widen to every other active provider.
 */
class SosAssignmentCandidatesController extends Controller
{
    use ApiResponse;

    public function index(Request $request, SosEvent $event)
    {
        abort_unless(
            SosRoles::isCoordinator($request->user()),
            403,
            'Only a coordinator can re-route an emergency.'
        );

        $careTeamProviderIds = CareAssignment::where('patient_user_id', $event->user_id)
            ->whereNull('ended_at')
            ->pluck('provider_id')
            ->all();

        $careTeam = CareProvider::with('user')
            ->whereIn('id', $careTeamProviderIds)
            ->get()
            ->map(fn (CareProvider $p) => $this->row($p, onCareTeam: true))
            ->values();

        // Everyone else who could take it. Suspended or pending accounts are
        // excluded: offering someone who cannot sign in wastes the one
        // resource an emergency does not have.
        $others = CareProvider::with('user')
            ->whereNotIn('id', $careTeamProviderIds)
            ->get()
            ->filter(fn (CareProvider $p) => $this->isAvailable($p->user))
            ->map(fn (CareProvider $p) => $this->row($p, onCareTeam: false))
            ->values();

        return $this->success([
            'care_team' => $careTeam->all(),
            'others' => $others->all(),
        ]);
    }

    private function isAvailable(?User $user): bool
    {
        if ($user === null) {
            return false;
        }
        $status = $user->status ?? 'active';

        return $status === 'active';
    }

    private function row(CareProvider $provider, bool $onCareTeam): array
    {
        return [
            'provider_id' => (string) $provider->id,
            'user_id' => $provider->user_id === null
                ? null
                : (string) $provider->user_id,
            'name' => $provider->name ?? $provider->user?->fullName() ?? 'Provider',
            'specialty' => $provider->specialty,
            'facility' => $provider->facility,
            'on_care_team' => $onCareTeam,
            'available' => $this->isAvailable($provider->user),
        ];
    }
}
