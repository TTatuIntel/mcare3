<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Admin / mCare-assistant workflow: review pending doctor & healthworker
 * registrations. Pending users are `users.approval_status='pending_approval'`.
 */
class ApprovalsController extends Controller
{
    use ApiResponse;

    private const CREDENTIAL_MIMES = 'pdf,jpg,jpeg,png,doc,docx';

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $status = $request->query('status', 'pending');

        $query = User::query()
            ->whereIn('role', ['doctor', 'mcare_assistant'])
            ->orderByDesc('created_at');

        if ($status === 'pending') {
            $query->where('approval_status', 'pending_approval');
        } elseif ($status !== 'all') {
            $query->where('approval_status', $status);
        }

        $applications = $query->limit(200)->get()->map(
            fn (User $u) => $this->applicationPayload($u),
        );

        return $this->success(['applications' => $applications]);
    }

    public function uploadCredential(Request $request, User $user)
    {
        if (! in_array($user->role, ['doctor', 'mcare_assistant'], true)) {
            return $this->error('Credential upload applies to healthworker applications only.', 422);
        }

        $data = $request->validate([
            'file' => 'required|file|max:10240|mimes:'.self::CREDENTIAL_MIMES,
        ]);

        if ($user->credential_document_path) {
            Storage::disk('public')->delete($user->credential_document_path);
        }

        $uploaded = $data['file'];
        $path = $uploaded->store('credentials/'.$user->id, 'public');
        $name = $uploaded->getClientOriginalName();

        $user->update([
            'credential_document_path' => $path,
            'credential_document_name' => $name,
        ]);

        $this->audit->record(
            $request->user(),
            'approval.credential_uploaded',
            $user->fullName(),
            'activity',
            ['target_user_id' => $user->id, 'file' => $name],
        );

        return $this->success(
            ['application' => $this->applicationPayload($user->fresh())],
            'Credential document uploaded.',
        );
    }

    public function streamCredential(Request $request, User $user): StreamedResponse|\Illuminate\Http\JsonResponse
    {
        if (! $user->credential_document_path) {
            return $this->error('No credential document on file.', 404);
        }

        if (! Storage::disk('public')->exists($user->credential_document_path)) {
            return $this->error('Credential file missing from storage.', 404);
        }

        return Storage::disk('public')->response(
            $user->credential_document_path,
            $user->credential_document_name ?? 'credential',
        );
    }

    public function approve(Request $request, User $user)
    {
        $data = $request->validate([
            'note' => 'nullable|string|max:280',
        ]);

        if ($user->approval_status !== 'pending_approval') {
            return $this->error('Application is not pending.', 422);
        }

        $user->update(['approval_status' => 'active']);

        AppNotification::create([
            'user_id' => $user->id,
            'kind' => 'approval',
            'title' => 'You\'re approved',
            'body' => 'Welcome to mCare — your account is active.',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request->user(),
            'approval.granted',
            $user->fullName().' ('.$user->roleToClient().')',
            'activity',
            ['target_user_id' => $user->id, 'note' => $data['note'] ?? null],
        );

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Approved.');
    }

    public function reject(Request $request, User $user)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($user->approval_status !== 'pending_approval') {
            return $this->error('Application is not pending.', 422);
        }

        $user->update(['approval_status' => 'rejected']);

        AppNotification::create([
            'user_id' => $user->id,
            'kind' => 'approval',
            'title' => 'Application not approved',
            'body' => $data['reason'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request->user(),
            'approval.rejected',
            $user->fullName(),
            'activity',
            ['target_user_id' => $user->id, 'reason' => $data['reason']],
        );

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Rejected.');
    }

    public function requestInfo(Request $request, User $user)
    {
        $data = $request->validate([
            'message' => 'required|string|min:4|max:280',
        ]);

        AppNotification::create([
            'user_id' => $user->id,
            'kind' => 'approval',
            'title' => 'More information needed',
            'body' => $data['message'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request->user(),
            'approval.info_requested',
            $user->fullName(),
            'activity',
            ['target_user_id' => $user->id, 'message' => $data['message']],
        );

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Information requested.');
    }

    private function applicationPayload(User $u): array
    {
        return [
            'id' => (string) $u->id,
            'name' => $u->fullName(),
            'email' => $u->email,
            'phone' => $u->phone,
            'role' => $u->roleToClient(),
            'specialty' => $u->specialty,
            'license_number' => $u->license_number,
            'status' => $u->approvalStatusToClient(),
            'submitted_at' => $u->created_at?->toIso8601String(),
            'has_credential_document' => (bool) $u->credential_document_path,
            'credential_document_name' => $u->credential_document_name,
        ];
    }
}
