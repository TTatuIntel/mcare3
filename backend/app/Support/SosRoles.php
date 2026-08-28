<?php

namespace App\Support;

use App\Models\User;

/**
 * Who counts as a coordinator on an emergency, and how they are named on the
 * response trail.
 *
 * `users.role` stores `mcare_assistant`; `mcareAssistant` is only the camel
 * cased alias handed to clients by {@see User::roleToClient()}. The SOS
 * controllers matched on the client alias, so every mCare Assistant — however
 * fully permissioned — was refused the candidate list and the response trail
 * by their own coordinator check. Both spellings are accepted here so the
 * mistake cannot be made a third time in a third file.
 */
class SosRoles
{
    /** @var list<string> */
    public const COORDINATOR_ROLES = ['admin', 'mcare_assistant', 'mcareAssistant'];

    public static function isCoordinator(?User $user): bool
    {
        return $user !== null
            && in_array($user->role, self::COORDINATOR_ROLES, true);
    }

    /** How this responder signs the trail. */
    public static function actorName(User $user): string
    {
        return match ($user->role) {
            'admin' => $user->fullName().' (Admin)',
            'mcare_assistant', 'mcareAssistant' => $user->fullName().' (mCare Assistant)',
            'doctor' => 'Dr. '.$user->fullName(),
            default => $user->fullName(),
        };
    }
}
