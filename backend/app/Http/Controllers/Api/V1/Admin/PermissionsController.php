<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AssistantPermission;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Admin-only management of mCare-Assistant permission grants. Assistants
 * cannot reach this controller (route is role:admin).
 */
class PermissionsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index()
    {
        $assistants = User::query()
            ->where('role', 'mcare_assistant')
            ->orderBy('first_name')
            ->get();

        $data = $assistants->map(function (User $u) {
            return [
                'user' => $u->toApiArray(),
                'permissions' => $u->assistantPermissions()->pluck('permission_key')->all(),
            ];
        });

        return $this->success([
            'grants' => $data,
            'available_keys' => AssistantPermission::KEYS,
        ]);
    }

    public function show(User $user)
    {
        if ($user->role !== 'mcare_assistant') {
            return $this->error('Permissions only apply to mCare assistants.', 422);
        }
        return $this->success([
            'user' => $user->toApiArray(),
            'permissions' => $user->assistantPermissions()->pluck('permission_key')->all(),
        ]);
    }

    public function sync(Request $request, User $user)
    {
        if ($user->role !== 'mcare_assistant') {
            return $this->error('Permissions only apply to mCare assistants.', 422);
        }

        $data = $request->validate([
            'permissions' => 'present|array',
            'permissions.*' => ['string', Rule::in(AssistantPermission::KEYS)],
        ]);

        $desired = array_values(array_unique($data['permissions']));
        $current = $user->assistantPermissions()->pluck('permission_key')->all();

        $toAdd = array_diff($desired, $current);
        $toRemove = array_diff($current, $desired);

        foreach ($toAdd as $key) {
            AssistantPermission::create([
                'user_id' => $user->id,
                'permission_key' => $key,
                'granted_by_user_id' => $request->user()->id,
            ]);
        }

        if (! empty($toRemove)) {
            $user->assistantPermissions()
                ->whereIn('permission_key', $toRemove)
                ->delete();
        }

        $this->audit->record(
            $request->user(),
            'permissions.synced',
            $user->fullName(),
            'security',
            [
                'target_user_id' => $user->id,
                'added' => array_values($toAdd),
                'removed' => array_values($toRemove),
            ],
        );

        return $this->success([
            'user' => $user->toApiArray(),
            'permissions' => $desired,
        ], 'Permissions updated.');
    }
}
