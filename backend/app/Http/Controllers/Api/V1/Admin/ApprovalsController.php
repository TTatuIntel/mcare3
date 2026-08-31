<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Mail\ApplicationUpdateMail;
use App\Mail\TemporaryCredentialsMail;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use App\Support\MailDispatcher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
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
            Storage::disk(config('mcare.private_disk', 'local'))->delete($user->credential_document_path);
            Storage::disk('public')->delete($user->credential_document_path);
        }

        $uploaded = $data['file'];
        $path = $uploaded->store('credentials/'.$user->id, config('mcare.private_disk', 'local'));
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

    public function streamCredential(Request $request, User $user): StreamedResponse|JsonResponse
    {
        if (! $user->credential_document_path) {
            return $this->error('No credential document on file.', 404);
        }

        $diskName = Storage::disk(config('mcare.private_disk', 'local'))
            ->exists($user->credential_document_path)
                ? config('mcare.private_disk', 'local')
                : 'public';

        if (! Storage::disk($diskName)->exists($user->credential_document_path)) {
            return $this->error('Credential file missing from storage.', 404);
        }

        return Storage::disk($diskName)->response(
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

        // An approved clinician has never signed in: the account was opened
        // for them by an administrator and has sat in pending_approval ever
        // since. Issuing credentials here, to the address the account was
        // opened with, is what turns an approval into something the person
        // can act on. It used to write an in-app notice to an account that
        // could not be opened to read it.
        $temporaryPassword = Str::random(12);

        // Persist the decision on the account itself, not just in the audit
        // log, so the dossier can show who approved this person and when.
        $user->update([
            'approval_status' => 'active',
            'approved_at' => now(),
            'approved_by' => $request->user()->id,
            'approval_note' => $data['note'] ?? null,
            'rejected_at' => null,
            'rejection_reason' => null,
            'password' => Hash::make($temporaryPassword),
            // Not optional. A password an administrator has seen is not the
            // user's password; it stops working once they set their own.
            'must_change_password' => true,
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ]);

        // Anything issued before this decision is void.
        $user->tokens()->delete();
        $user->fcmTokens()->delete();

        $emailSent = $this->dispatchMail(
            $user,
            new TemporaryCredentialsMail(
                $user,
                $temporaryPassword,
                (string) config('mcare.frontend_url'),
                approved: true,
            ),
        );

        AppNotification::create([
            'user_id' => $user->id,
            'kind' => 'approval',
            'title' => 'You\'re approved',
            'body' => 'Welcome to mCare — your account is active. Check your '
                .'email for your temporary sign-in password.',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request->user(),
            'approval.granted',
            $user->fullName().' ('.$user->roleToClient().')',
            'activity',
            [
                'target_user_id' => $user->id,
                'note' => $data['note'] ?? null,
                'credentials_emailed' => $emailSent,
            ],
        );

        return $this->success(
            [
                'user' => $user->fresh()->toApiArray(),
                'email_sent' => $emailSent,
            ],
            $emailSent
                ? 'Approved. Sign-in details emailed to '.$user->email.'.'
                : 'Approved, but the email could not be sent. Use a password reset to try again.',
        );
    }

    public function reject(Request $request, User $user)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($user->approval_status !== 'pending_approval') {
            return $this->error('Application is not pending.', 422);
        }

        $user->update([
            'approval_status' => 'rejected',
            'rejected_at' => now(),
            'rejection_reason' => $data['reason'],
        ]);

        $emailSent = $this->dispatchMail(
            $user,
            new ApplicationUpdateMail(
                $user,
                ApplicationUpdateMail::KIND_REJECTED,
                $data['reason'],
                (string) config('mcare.frontend_url'),
            ),
        );

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
            [
                'target_user_id' => $user->id,
                'reason' => $data['reason'],
                'emailed' => $emailSent,
            ],
        );

        return $this->success(
            ['user' => $user->fresh()->toApiArray(), 'email_sent' => $emailSent],
            $emailSent
                ? 'Rejected. The applicant was emailed the reason.'
                : 'Rejected, but the email could not be sent.',
        );
    }

    public function requestInfo(Request $request, User $user)
    {
        $data = $request->validate([
            'message' => 'required|string|min:4|max:280',
        ]);

        // The applicant cannot sign in — that is the whole reason they are
        // being asked for something. Email is the only channel that reaches
        // them, so a failure to send is a failure of the request itself.
        $emailSent = $this->dispatchMail(
            $user,
            new ApplicationUpdateMail(
                $user,
                ApplicationUpdateMail::KIND_INFO_REQUESTED,
                $data['message'],
                (string) config('mcare.frontend_url'),
            ),
        );

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
            [
                'target_user_id' => $user->id,
                'message' => $data['message'],
                'emailed' => $emailSent,
            ],
        );

        if (! $emailSent) {
            return $this->error(
                'The request could not be emailed to '.$user->email
                    .'. The applicant cannot see in-app messages until they are approved.',
                502,
                ['user' => $user->fresh()->toApiArray(), 'email_sent' => false],
            );
        }

        return $this->success(
            ['user' => $user->fresh()->toApiArray(), 'email_sent' => true],
            'Emailed to '.$user->email.'.',
        );
    }

    /**
     * Send, and say whether it left. Delivery is never assumed: the caller
     * decides what a failure means, because for an approval it is an
     * inconvenience and for an information request it is the whole action.
     */
    private function dispatchMail(User $user, $mailable): bool
    {
        if (blank($user->email)) {
            return false;
        }

        return MailDispatcher::send(
            $user->email,
            $mailable,
            ['purpose' => 'application_update', 'user_id' => $user->id],
        );
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
