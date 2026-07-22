<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AssistantPermission extends Model
{
    /**
     * Canonical permission keys (matches AssistantPermissions in
     * lib/shared/auth/auth_state.dart).
     */
    public const KEYS = [
        'can_approve_healthworkers',
        'can_manage_care_requests',
        'can_assign_patients',
        'can_create_users',
        'can_change_user_types',
        'can_register_admin',
        'can_register_assistant',
        'can_view_activity_logs',
        'can_view_security_incidents',
        'can_access_emergency_location',
        'can_manage_advertising',
        'can_manage_vital_catalog',
    ];

    protected $fillable = [
        'user_id',
        'permission_key',
        'granted_by_user_id',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function grantedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'granted_by_user_id');
    }
}
