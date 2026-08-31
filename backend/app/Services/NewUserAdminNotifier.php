<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\User;

final class NewUserAdminNotifier
{
    /** Create one quiet, in-app notification for every active administrator. */
    public static function notify(User $joined): void
    {
        $role = match ($joined->role) {
            'doctor' => 'Doctor',
            'healthworker' => 'Health worker',
            'mcare_assistant' => 'mCare assistant',
            'admin' => 'Administrator',
            default => 'Patient',
        };
        $name = $joined->fullName() !== '' ? $joined->fullName() : $joined->email;

        User::query()
            ->where('role', 'admin')
            ->where('approval_status', 'active')
            ->where('id', '!=', $joined->id)
            ->each(function (User $admin) use ($joined, $name, $role): void {
                AppNotification::create([
                    'user_id' => $admin->id,
                    'kind' => 'new_user',
                    'title' => 'New '.$role.' joined',
                    'body' => $name.' created an mCare account.',
                    'action_route' => '/admin/users',
                    'action_arguments' => ['user_id' => (string) $joined->id],
                    'read' => false,
                    'resolved' => false,
                ]);
            });
    }
}
