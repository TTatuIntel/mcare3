<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Mail\UserInviteMail;
use App\Models\User;
use App\Models\UserInvite;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Admin / mCare-assistant user management. Permission gates:
 *  - listing / status / pw-reset: can_create_users
 *  - role change: can_change_user_types
 *  - role=admin create: can_register_admin
 *  - role=mcare_assistant create: can_register_assistant
 */
class UsersController extends Controller
{
    use ApiResponse;

    private const ROLES = ['patient', 'doctor', 'mcare_assistant', 'admin'];

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $role = $request->query('role');
        $status = $request->query('status');
        $q = $request->query('query');

        $query = User::query()->orderByDesc('created_at');

        if ($role) {
            $query->where('role', $this->normalizeRoleFromClient($role));
        }
        if ($status) {
            $query->where('approval_status', $status);
        }
        if ($q) {
            $like = '%'.str_replace('%', '\\%', $q).'%';
            $query->where(function ($w) use ($like) {
                $w->where('first_name', 'like', $like)
                  ->orWhere('last_name', 'like', $like)
                  ->orWhere('email', 'like', $like)
                  ->orWhere('phone', 'like', $like)
                  ->orWhere('unique_id', 'like', $like);
            });
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(100, max(10, (int) $request->query('per_page', 25)));

        $total = $query->count();
        $users = $query->forPage($page, $perPage)->get()
            ->map(fn (User $u) => $u->toApiArray());

        return $this->success([
            'users' => $users,
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
            ],
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'first_name' => 'required|string|max:100',
            'last_name' => 'required|string|max:100',
            'email' => 'required|email|max:255|unique:users,email',
            'phone' => 'nullable|string|max:30',
            'role' => ['required', Rule::in(['patient', 'doctor', 'healthworker', 'mcareAssistant', 'mcare_assistant', 'admin'])],
            'specialty' => 'nullable|string|max:120',
            'license_number' => 'nullable|string|max:80',
        ]);

        $actor = $request->user();
        $clientRole = $data['role'];
        $serverRole = $this->normalizeRoleFromClient($clientRole);

        // Role-aware permission gate.
        if ($actor->role !== 'admin') {
            $requiredKey = match ($serverRole) {
                'admin' => 'can_register_admin',
                'mcare_assistant' => 'can_register_assistant',
                default => 'can_create_users',
            };
            if (! $actor->hasAssistantPermission($requiredKey)) {
                return $this->error('Permission denied — missing '.$requiredKey.'.', 403);
            }
        }

        $tempPassword = Str::random(12);

        $user = User::create([
            'unique_id' => User::generateUniqueId(),
            'first_name' => $data['first_name'],
            'last_name' => $data['last_name'],
            'email' => strtolower($data['email']),
            'phone' => $data['phone'] ?? null,
            'role' => $serverRole,
            'specialty' => $data['specialty'] ?? null,
            'license_number' => $data['license_number'] ?? null,
            'approval_status' => in_array($serverRole, ['doctor', 'mcare_assistant'], true)
                ? 'pending_approval'
                : 'active',
            'password' => Hash::make($tempPassword),
            'must_change_password' => true,
            'email_verified_at' => null,
        ]);

        $inviteToken = null;
        if (in_array($serverRole, ['doctor', 'mcare_assistant', 'admin'], true)) {
            $inviteToken = Str::random(48);
            UserInvite::create([
                'user_id' => $user->id,
                'token' => $inviteToken,
                'expires_at' => now()->addDays(7),
            ]);
        }

        $this->audit->record(
            $actor,
            'user.created',
            $user->fullName().' ('.$user->roleToClient().')',
            'activity',
            ['target_user_id' => $user->id],
        );

        $emailSent = $inviteToken
            ? $this->dispatchInviteEmail($user, $inviteToken)
            : false;

        return $this->success([
            'user' => $user->toApiArray(),
            'temp_password' => $tempPassword,
            'invite_token' => $inviteToken,
            'email_sent' => $emailSent,
        ], 'User created.', 201);
    }

    public function changeRole(Request $request, User $user)
    {
        $data = $request->validate([
            'role' => ['required', Rule::in(['patient', 'doctor', 'healthworker', 'mcareAssistant', 'mcare_assistant', 'admin'])],
            'reason' => 'required|string|min:4|max:280',
        ]);

        $actor = $request->user();
        $newServerRole = $this->normalizeRoleFromClient($data['role']);

        if ($actor->role !== 'admin' && ! $actor->hasAssistantPermission('can_change_user_types')) {
            return $this->error('Permission denied — cannot change user roles.', 403);
        }

        // Assistant cannot promote anyone to admin without can_register_admin.
        if ($actor->role !== 'admin' && $newServerRole === 'admin') {
            if (! $actor->hasAssistantPermission('can_register_admin')) {
                return $this->error('Permission denied — cannot promote to admin.', 403);
            }
        }
        if ($actor->role !== 'admin' && $newServerRole === 'mcare_assistant') {
            if (! $actor->hasAssistantPermission('can_register_assistant')) {
                return $this->error('Permission denied — cannot promote to assistant.', 403);
            }
        }

        // Prevent self-demotion lockouts.
        if ($actor->id === $user->id && $newServerRole !== $actor->role) {
            return $this->error('You cannot change your own role.', 422);
        }

        $oldRole = $user->roleToClient();
        $user->update(['role' => $newServerRole]);

        $this->audit->record(
            $actor,
            'user.role_changed',
            $user->fullName().": $oldRole → ".$user->roleToClient(),
            'activity',
            [
                'target_user_id' => $user->id,
                'from_role' => $oldRole,
                'to_role' => $user->roleToClient(),
                'reason' => $data['reason'],
            ],
        );

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Role updated.');
    }

    public function changeStatus(Request $request, User $user)
    {
        $data = $request->validate([
            'status' => ['required', Rule::in(['active', 'suspended', 'pending_approval'])],
        ]);

        if ($request->user()->id === $user->id && $data['status'] !== 'active') {
            return $this->error('You cannot suspend your own account.', 422);
        }

        $previous = $user->approval_status;
        $user->update(['approval_status' => $data['status']]);

        $this->audit->record(
            $request->user(),
            'user.status_changed',
            $user->fullName().": $previous → ".$data['status'],
            'activity',
            [
                'target_user_id' => $user->id,
                'from_status' => $previous,
                'to_status' => $data['status'],
            ],
        );

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Status updated.');
    }

    public function resetPassword(Request $request, User $user)
    {
        $temp = Str::random(12);
        $user->update([
            'password' => Hash::make($temp),
            'must_change_password' => true,
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ]);

        // Force re-auth with the new temporary password.
        $user->tokens()->delete();

        $this->audit->record(
            $request->user(),
            'user.password_reset',
            $user->fullName(),
            'security',
            ['target_user_id' => $user->id],
        );

        return $this->success([
            'temp_password' => $temp,
            'user' => $user->fresh()->toApiArray(),
        ], 'Temporary password issued. Share it securely — user must change it on next sign-in.');
    }

    public function unlock(Request $request, User $user)
    {
        if ($request->user()->id === $user->id) {
            return $this->error('You cannot unlock your own session this way.', 422);
        }

        $wasLocked = $user->isLocked();
        $user->clearLockout();

        $this->audit->record(
            $request->user(),
            'user.unlocked',
            $user->fullName(),
            'security',
            [
                'target_user_id' => $user->id,
                'was_locked' => $wasLocked,
            ],
        );

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
        ], $wasLocked ? 'Account unlocked.' : 'Login attempts cleared.');
    }

    public function resendInvite(Request $request, User $user)
    {
        if (! in_array($user->role, ['doctor', 'mcare_assistant', 'admin'], true)) {
            return $this->error('This account type does not use invites.', 422);
        }

        if ($user->email_verified_at !== null) {
            return $this->error('Invite already accepted — user has completed setup.', 422);
        }

        UserInvite::query()
            ->where('user_id', $user->id)
            ->whereNull('accepted_at')
            ->update(['expires_at' => now()]);

        $inviteToken = Str::random(48);
        $expiresAt = now()->addDays(7);

        UserInvite::create([
            'user_id' => $user->id,
            'token' => $inviteToken,
            'expires_at' => $expiresAt,
        ]);

        $this->audit->record(
            $request->user(),
            'user.invite_resent',
            $user->fullName(),
            'activity',
            ['target_user_id' => $user->id],
        );

        $emailSent = $this->dispatchInviteEmail($user, $inviteToken);

        return $this->success([
            'invite_token' => $inviteToken,
            'expires_at' => $expiresAt->toIso8601String(),
            'email_sent' => $emailSent,
        ], 'Invite reissued.');
    }

    private function dispatchInviteEmail(User $user, string $inviteToken): bool
    {
        try {
            Mail::to($user->email)->send(new UserInviteMail(
                $user,
                $inviteToken,
                config('mcare.frontend_url'),
            ));

            return true;
        } catch (\Throwable $e) {
            report($e);

            return false;
        }
    }

    private function normalizeRoleFromClient(string $clientRole): string
    {
        return match ($clientRole) {
            'mcareAssistant', 'mcare_assistant' => 'mcare_assistant',
            'healthworker' => 'doctor',
            default => $clientRole,
        };
    }
}
