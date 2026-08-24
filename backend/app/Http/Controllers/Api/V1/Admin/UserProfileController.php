<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\AuditService;
use App\Services\UserDossierService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The complete dossier for any account, whatever its role.
 *
 * Admin screens previously showed a rich clinical sheet for patients and a
 * three-line card for everyone else, which made it easy to act on a doctor or
 * assistant without seeing their approval trail or caseload. This endpoint
 * returns one uniform shape for every role so the client renders the same
 * full profile regardless of who is being looked at.
 *
 * Reads of a clinical record are themselves auditable events, so every
 * patient dossier fetch is recorded.
 */
class UserProfileController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly UserDossierService $dossiers,
        private readonly AuditService $audit,
    ) {}

    public function show(Request $request, User $user)
    {
        $dossier = $this->dossiers->build($user);

        if ($user->role === 'patient') {
            $this->audit->record(
                $request->user(),
                'patient.profile_viewed',
                $user->fullName(),
                'security',
                [
                    'patient_user_id' => $user->id,
                    'target_user_id' => $user->id,
                ],
            );
        }

        return $this->success($dossier);
    }
}
