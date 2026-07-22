<?php

namespace App\Services;

use App\Models\AuditEntry;
use App\Models\User;

/**
 * Centralised audit-trail writer. Every admin / assistant write that
 * should be auditable goes through this service so the column shape
 * stays consistent.
 */
class AuditService
{
    public function record(
        User $actor,
        string $action,
        ?string $target = null,
        string $category = 'activity',
        array $meta = []
    ): AuditEntry {
        $roleLabel = match ($actor->role) {
            'admin' => 'Admin',
            'mcare_assistant' => 'mCare Assistant',
            'doctor' => 'Doctor',
            default => ucfirst($actor->role),
        };

        return AuditEntry::create([
            'actor_user_id' => $actor->id,
            'actor_label' => $actor->fullName().' ('.$roleLabel.')',
            'action' => $action,
            'target' => $target,
            'category' => $category,
            'meta' => $meta ?: null,
            'happened_at' => now(),
        ]);
    }
}
