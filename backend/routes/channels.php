<?php

use App\Http\Controllers\Api\V1\DoctorAccess;
use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});

// Per-user private channel for role-session and direct-recipient changes.
Broadcast::channel('user.{id}', function (User $user, int $id) {
    return (int) $user->id === $id;
});

// Payload-free application invalidations such as announcement and catalog
// changes. REST authorization still controls the subsequent data read.
Broadcast::channel('app', fn (User $user) => $user->exists);

// Platform-wide operational invalidations for administrators and delegated
// assistants. No personal or clinical payload is broadcast on this channel.
Broadcast::channel('staff', function (User $user) {
    return in_array($user->role, ['admin', 'mcare_assistant'], true);
});

// README §7.1 — care-team channel per patient. Only providers currently
// assigned to that patient (or the patient themselves, or admin/assistant)
// may subscribe. Bad actors on the WS layer get 403 at the /broadcasting/auth
// handshake — never at message-delivery time.
Broadcast::channel('care-team.{patientId}', function (User $user, int $patientId) {
    if ((int) $user->id === $patientId) {
        return true;
    }
    if (in_array($user->role, ['admin', 'mcare_assistant'], true)) {
        return true;
    }
    if ($user->role === 'doctor') {
        return in_array($patientId, DoctorAccess::caseloadPatientIds($user), true);
    }

    return false;
});
