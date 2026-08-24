<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Mail\EmailVerificationMail;
use App\Mail\PasswordResetMail;
use App\Models\EmailVerificationCode;
use App\Models\User;
use App\Models\UserInvite;
use App\Support\ApiResponse;
use App\Support\AppleIdTokenVerifier;
use App\Support\GoogleIdTokenVerifier;
use App\Support\GoogleOAuth;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    use ApiResponse;

    public function register(Request $request)
    {
        $data = $request->validate([
            'first_name' => 'required|string|max:100',
            'last_name' => 'required|string|max:100',
            'email' => 'required|email|max:255|unique:users,email',
            'phone' => 'nullable|string|max:30',
            'password' => 'required|string|min:8',
            'role' => 'nullable|in:patient',
        ]);

        $user = User::create([
            'unique_id' => User::generateUniqueId(),
            'first_name' => $data['first_name'],
            'last_name' => $data['last_name'],
            'email' => strtolower($data['email']),
            'phone' => $data['phone'] ?? null,
            'role' => 'patient',
            'approval_status' => 'active',
            'password' => $data['password'],
            'email_verified_at' => now(),
        ]);

        return $this->authPayload($user, 'Account created successfully.', 201);
    }

    public function login(Request $request)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'password' => 'required|string',
        ]);

        $identifier = trim($data['identifier']);
        $email = strtolower($identifier);

        // Accept common demo aliases from older docs / UI defaults.
        $email = match ($email) {
            'amara.o@example.com' => 'amara.okonkwo@example.com',
            'dr.mensah@example.com' => 'dr.mensah@mcare.health',
            'sarah.a@example.com', 'dr.adeyemi@example.com' => 'dr.adeyemi@mcare.health',
            'assistant@mcare.app' => 'assistant@mcare.health',
            default => $email,
        };

        $user = User::query()
            ->where(function ($q) use ($email, $identifier) {
                $q->whereRaw('LOWER(email) = ?', [$email])
                    ->orWhere('phone', $identifier)
                    ->orWhere('unique_id', $identifier);
            })
            ->first();

        if ($user && $user->isLocked()) {
            $until = $user->locked_until?->toIso8601String();

            return $this->error(
                'Account locked after too many failed sign-in attempts. Contact an admin for a temporary password or unlock, or try again after '.$until.'.',
                423,
            );
        }

        if (! $user || ! $user->password || ! Hash::check($data['password'], $user->password)) {
            if ($user) {
                $user->registerFailedLogin();
                if ($user->fresh()->isLocked()) {
                    return $this->error(
                        'Account locked after too many failed sign-in attempts. Contact an admin for unlock or a temporary password.',
                        423,
                    );
                }
            }

            throw ValidationException::withMessages([
                'identifier' => ['Invalid credentials.'],
            ]);
        }

        if ($user->approval_status === 'suspended') {
            return $this->error('Account suspended.', 403);
        }

        $user->clearLockout();

        return $this->authPayload($user->fresh(), 'Signed in successfully.');
    }

    public function google(Request $request, GoogleIdTokenVerifier $verifier)
    {
        $data = $request->validate([
            'id_token' => 'required|string',
            'create_account' => 'sometimes|boolean',
            'email' => 'nullable|email',
            'first_name' => 'nullable|string|max:100',
            'last_name' => 'nullable|string|max:100',
        ]);

        $isMock = str_starts_with($data['id_token'], 'mock');

        if ($isMock) {
            return $this->googleMockSignIn($data);
        }

        $payload = $verifier->verify($data['id_token']);
        if (! $payload) {
            return $this->error('Invalid or expired Google sign-in. Please try again.', 401);
        }

        $resolved = $this->resolveGoogleUser($payload, (bool) ($data['create_account'] ?? false));
        if ($resolved instanceof \Illuminate\Http\JsonResponse) {
            return $resolved;
        }

        return $this->authPayload($resolved, 'Signed in with Google.');
    }

    /**
     * Sign in with Apple. Mirrors {@see google()}: verifies the Apple identity
     * token, then resolves or creates the account keyed on the Apple `sub`.
     *
     * Apple only returns the user's name on the *first* authorization, and never
     * inside the identity token, so the client forwards `first_name`/`last_name`
     * for account creation.
     */
    public function apple(Request $request, AppleIdTokenVerifier $verifier)
    {
        $data = $request->validate([
            'id_token' => 'required|string',
            'create_account' => 'sometimes|boolean',
            'email' => 'nullable|email',
            'first_name' => 'nullable|string|max:100',
            'last_name' => 'nullable|string|max:100',
        ]);

        if (str_starts_with($data['id_token'], 'mock')) {
            return $this->appleMockSignIn($data);
        }

        $payload = $verifier->verify($data['id_token']);
        if (! $payload) {
            return $this->error('Invalid or expired Apple sign-in. Please try again.', 401);
        }

        $resolved = $this->resolveAppleUser(
            $payload,
            (bool) ($data['create_account'] ?? false),
            $data['first_name'] ?? null,
            $data['last_name'] ?? null,
        );
        if ($resolved instanceof \Illuminate\Http\JsonResponse) {
            return $resolved;
        }

        return $this->authPayload($resolved, 'Signed in with Apple.');
    }

    /**
     * Starts Google OAuth (full-page redirect — works in Firefox & mobile).
     */
    public function googleRedirect(Request $request)
    {
        $data = $request->validate([
            'return_to' => 'required|url',
            'create_account' => 'sometimes|boolean',
        ]);

        if (! config('services.google.client_id') || ! config('services.google.client_secret')) {
            return $this->error('Google Sign-In is not configured on the server.', 503);
        }

        if (! GoogleOAuth::isAllowedReturnTo($data['return_to'])) {
            return $this->error('Invalid return URL for Google Sign-In.', 422);
        }

        return redirect(GoogleOAuth::buildAuthorizeUrl(
            $data['return_to'],
            $request->boolean('create_account'),
        ));
    }

    /**
     * Google OAuth callback — exchanges code, signs user in, redirects to Flutter.
     */
    public function googleCallback(Request $request, GoogleIdTokenVerifier $verifier)
    {
        $state = (string) $request->query('state', '');
        $oauth = $state !== '' ? \Illuminate\Support\Facades\Cache::pull("google_oauth:{$state}") : null;
        $returnTo = is_array($oauth) ? ($oauth['return_to'] ?? '/') : '/';
        $createAccount = is_array($oauth) ? (bool) ($oauth['create_account'] ?? false) : false;

        if ($request->filled('error')) {
            return redirect($this->googleReturnUrl($returnTo, [
                'error' => (string) $request->query('error_description', $request->query('error')),
            ]));
        }

        if (! is_array($oauth) || ! $request->filled('code')) {
            return redirect($this->googleReturnUrl($returnTo, [
                'error' => 'Google sign-in was interrupted. Please try again.',
            ]));
        }

        $tokens = GoogleOAuth::exchangeCode((string) $request->query('code'));
        $idToken = is_array($tokens) ? ($tokens['id_token'] ?? null) : null;
        if (! $idToken) {
            return redirect($this->googleReturnUrl($returnTo, [
                'error' => 'Could not complete Google sign-in. Check redirect URI in Google Cloud Console.',
            ]));
        }

        $payload = $verifier->verify($idToken);
        if (! $payload) {
            return redirect($this->googleReturnUrl($returnTo, [
                'error' => 'Invalid Google account response. Please try again.',
            ]));
        }

        $user = $this->resolveGoogleUser($payload, $createAccount);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            $body = $user->getData(true);
            $message = is_array($body) ? ($body['message'] ?? 'Sign-in failed.') : 'Sign-in failed.';

            return redirect($this->googleReturnUrl($returnTo, ['error' => $message]));
        }

        $token = $user->createToken('mcare-web')->plainTextToken;

        return redirect($this->googleReturnUrl($returnTo, [
            'token' => $token,
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile()->exists(),
        ]));
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function resolveGoogleUser(array $payload, bool $createAccount): User|\Illuminate\Http\JsonResponse
    {
        $googleId = (string) $payload['sub'];
        $email = strtolower((string) $payload['email']);
        $firstName = (string) ($payload['given_name'] ?? 'Patient');
        $lastName = (string) ($payload['family_name'] ?? '');

        $user = User::query()
            ->where(function ($query) use ($googleId, $email) {
                $query->where('google_id', $googleId)
                    ->orWhere('email', $email);
            })
            ->first();

        if ($user) {
            if ($user->approval_status === 'suspended') {
                return $this->error('Account suspended.', 403);
            }

            $updates = [];
            if (! $user->google_id) {
                $updates['google_id'] = $googleId;
            }
            if (! $user->email_verified_at) {
                $updates['email_verified_at'] = now();
            }
            if ($updates !== []) {
                $user->update($updates);
            }

            return $user;
        }

        if ($createAccount) {
            return User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $firstName,
                'last_name' => $lastName,
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'google_id' => $googleId,
                'email_verified_at' => now(),
            ]);
        }

        return $this->error(
            'No mCare account exists for this Google email. Use Create account or register with email first.',
            404,
        );
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function googleReturnUrl(string $returnTo, array $data): string
    {
        $fragment = base64_encode(json_encode($data, JSON_THROW_ON_ERROR));

        return strtok($returnTo, '#').'#mcare_google='.rawurlencode($fragment);
    }

    /**
     * Dev fallback when the Flutter mock picker is used with a mock token.
     */
    private function googleMockSignIn(array $data)
    {
        $email = strtolower($data['email'] ?? '');
        if ($email === '') {
            return $this->error('Email is required for mock Google sign-in.', 422);
        }

        $user = User::query()->where('email', $email)->first();

        if (! $user && ! ($data['create_account'] ?? false)) {
            return $this->error('No account found. Please register first.', 404);
        }

        if (! $user) {
            $user = User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $data['first_name'] ?? 'Patient',
                'last_name' => $data['last_name'] ?? 'User',
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'google_id' => 'mock:'.$email,
                'email_verified_at' => now(),
            ]);
        } elseif (! $user->google_id) {
            $user->update(['google_id' => 'mock:'.$email]);
        }

        return $this->authPayload($user, 'Signed in with Google (mock).');
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function resolveAppleUser(
        array $payload,
        bool $createAccount,
        ?string $firstName,
        ?string $lastName,
    ): User|\Illuminate\Http\JsonResponse {
        $appleId = (string) $payload['sub'];
        // Apple relay addresses count as verified; email may be absent on repeat
        // logins, so fall back to matching purely on the Apple subject id.
        $email = isset($payload['email']) ? strtolower((string) $payload['email']) : null;

        $user = User::query()
            ->where('apple_id', $appleId)
            ->when($email !== null, fn ($q) => $q->orWhere('email', $email))
            ->first();

        if ($user) {
            if ($user->approval_status === 'suspended') {
                return $this->error('Account suspended.', 403);
            }

            $updates = [];
            if (! $user->apple_id) {
                $updates['apple_id'] = $appleId;
            }
            if (! $user->email_verified_at) {
                $updates['email_verified_at'] = now();
            }
            if ($updates !== []) {
                $user->update($updates);
            }

            return $user;
        }

        if ($createAccount) {
            if ($email === null) {
                return $this->error(
                    'Apple did not share an email for this account. Please register with email first.',
                    422,
                );
            }

            return User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $firstName ?: 'Patient',
                'last_name' => $lastName ?: '',
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'apple_id' => $appleId,
                'email_verified_at' => now(),
            ]);
        }

        return $this->error(
            'No mCare account exists for this Apple ID. Use Create account or register with email first.',
            404,
        );
    }

    /**
     * Dev fallback when the Flutter mock Apple flow is used with a mock token.
     *
     * @param  array<string, mixed>  $data
     */
    private function appleMockSignIn(array $data)
    {
        $email = strtolower($data['email'] ?? '');
        if ($email === '') {
            return $this->error('Email is required for mock Apple sign-in.', 422);
        }

        $user = User::query()->where('email', $email)->first();

        if (! $user && ! ($data['create_account'] ?? false)) {
            return $this->error('No account found. Please register first.', 404);
        }

        if (! $user) {
            $user = User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $data['first_name'] ?? 'Patient',
                'last_name' => $data['last_name'] ?? 'User',
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'apple_id' => 'mock:'.$email,
                'email_verified_at' => now(),
            ]);
        } elseif (! $user->apple_id) {
            $user->update(['apple_id' => 'mock:'.$email]);
        }

        return $this->authPayload($user, 'Signed in with Apple (mock).');
    }

    public function forgotPassword(Request $request)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
        ]);

        $identifier = trim($data['identifier']);
        $user = User::query()
            ->where('email', strtolower($identifier))
            ->orWhere('phone', $identifier)
            ->first();

        // Always return success to avoid account enumeration.
        if ($user) {
            $token = Str::random(64);
            DB::table('password_reset_tokens')->updateOrInsert(
                ['email' => $user->email],
                ['token' => Hash::make($token), 'created_at' => now()],
            );

            try {
                Mail::to($user->email)->send(new PasswordResetMail(
                    $user,
                    $token,
                    config('mcare.frontend_url'),
                ));
            } catch (\Throwable $e) {
                report($e);
            }
        }

        return $this->success(null, 'If an account exists, reset instructions were sent.');
    }

    public function resetPassword(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'token' => 'required|string',
            'password' => 'required|string|min:8',
        ]);

        $row = DB::table('password_reset_tokens')
            ->where('email', strtolower($data['email']))
            ->first();

        if (! $row || ! Hash::check($data['token'], $row->token)) {
            return $this->error('Invalid or expired reset token.', 422);
        }

        $user = User::where('email', strtolower($data['email']))->first();
        if (! $user) {
            return $this->error('Account not found.', 404);
        }

        $user->update([
            'password' => $data['password'],
            'must_change_password' => false,
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ]);
        DB::table('password_reset_tokens')->where('email', $user->email)->delete();

        return $this->success(null, 'Password updated. You can sign in now.');
    }

    public function verifyOtp(Request $request)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'code' => 'required|string|size:6',
            'purpose' => 'nullable|string|in:email_verify,login',
        ]);

        $user = User::query()
            ->where('email', strtolower(trim($data['identifier'])))
            ->orWhere('phone', trim($data['identifier']))
            ->first();

        if (! $user) {
            return $this->error('Invalid verification code.', 422);
        }

        $purpose = $data['purpose'] ?? 'email_verify';
        $record = EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', $purpose)
            ->where('code', $data['code'])
            ->orderByDesc('created_at')
            ->first();

        if (! $record || ! $record->isValid()) {
            return $this->error('Invalid or expired verification code.', 422);
        }

        $record->update(['used_at' => now()]);
        if ($purpose === 'email_verify') {
            $user->update(['email_verified_at' => now()]);
        }

        return $this->authPayload($user, 'Verified successfully.');
    }

    public function acceptInvite(Request $request)
    {
        $data = $request->validate([
            'token' => 'required|string',
            'password' => 'required|string|min:8',
        ]);

        $invite = UserInvite::query()->where('token', $data['token'])->first();
        if (! $invite || ! $invite->isValid()) {
            return $this->error('Invite link is invalid or has expired.', 422);
        }

        $user = $invite->user;
        $user->update([
            'password' => $data['password'],
            'must_change_password' => false,
            'failed_login_attempts' => 0,
            'locked_until' => null,
            'email_verified_at' => $user->email_verified_at ?? now(),
            'approval_status' => $user->approval_status === 'pending_approval'
                ? 'active'
                : $user->approval_status,
        ]);
        $invite->update(['accepted_at' => now()]);

        return $this->authPayload($user->fresh(), 'Invite accepted — welcome to mCare.');
    }

    public function me(Request $request)
    {
        $user = $request->user();

        $payload = [
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile()->exists(),
        ];

        if ($user->role === 'mcare_assistant') {
            $payload['assistant_permissions'] = $user->assistantPermissions()
                ->pluck('permission_key')
                ->all();
        }

        return $this->success($payload);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()?->delete();

        return $this->success(null, 'Signed out.');
    }

    public function updateProfile(Request $request)
    {
        $data = $request->validate([
            'first_name'     => 'required|string|max:80',
            'last_name'      => 'required|string|max:80',
            'phone'          => 'required|string|max:30',
            'specialty'      => 'nullable|string|max:120',
            'license_number' => 'nullable|string|max:80',
        ]);

        $user = $request->user();

        $updates = [
            'first_name' => $data['first_name'],
            'last_name'  => $data['last_name'],
            'phone'      => $data['phone'],
        ];

        // Specialty / licence are only meaningful for clinicians. Accept them
        // when the field is present so a doctor can maintain their own record.
        if ($user->role === 'doctor') {
            if ($request->has('specialty')) {
                $updates['specialty'] = $data['specialty'] ?? null;
            }
            if ($request->has('license_number')) {
                $updates['license_number'] = $data['license_number'] ?? null;
            }
        }

        $user->update($updates);

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Profile updated.');
    }

    public function changeEmail(Request $request)
    {
        $data = $request->validate([
            'current_password' => 'required|string',
            'new_email'        => 'required|email|max:255',
        ]);

        $user = $request->user();

        if (! $user->password || ! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['Current password is incorrect.'],
            ]);
        }

        $newEmail = strtolower(trim($data['new_email']));
        if ($newEmail === strtolower((string) $user->email)) {
            throw ValidationException::withMessages([
                'new_email' => ['That is already your email address.'],
            ]);
        }
        if (User::where('email', $newEmail)->where('id', '!=', $user->id)->exists()) {
            throw ValidationException::withMessages([
                'new_email' => ['That email is already in use by another account.'],
            ]);
        }

        $user->update([
            'email' => $newEmail,
            'email_verified_at' => null,
        ]);

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        EmailVerificationCode::create([
            'user_id' => $user->id,
            'code' => $code,
            'purpose' => 'email_verify',
            'expires_at' => now()->addMinutes(30),
        ]);

        try {
            Mail::to($newEmail)->send(new EmailVerificationMail($user->fresh(), $code));
        } catch (\Throwable $e) {
            report($e);
        }

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
        ], 'Email updated. We sent a 6-digit verification code to your new address.');
    }

    public function uploadAvatar(Request $request)
    {
        $request->validate([
            'avatar' => 'required|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        $user = $request->user();

        // Remove the previous file so avatars don't accumulate on disk.
        if ($user->avatar_path) {
            Storage::disk('public')->delete($user->avatar_path);
        }

        $path = $request->file('avatar')->store('avatars', 'public');
        $user->update(['avatar_path' => $path]);

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Photo updated.');
    }

    public function deleteAvatar(Request $request)
    {
        $user = $request->user();
        if ($user->avatar_path) {
            Storage::disk('public')->delete($user->avatar_path);
            $user->update(['avatar_path' => null]);
        }

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Photo removed.');
    }

    public function changePassword(Request $request)
    {
        $data = $request->validate([
            'current_password' => 'required|string',
            'new_password' => 'required|string|min:8',
        ]);

        $user = $request->user();

        if (! $user->password || ! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['Current password is incorrect.'],
            ]);
        }

        $user->update([
            'password' => $data['new_password'],
            'must_change_password' => false,
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ]);

        // Invalidate other sessions / tokens — keep the current one.
        $current = $user->currentAccessToken();
        $user->tokens()->where('id', '!=', $current?->id)->delete();

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
        ], 'Password updated.');
    }

    private function authPayload(User $user, string $message, int $status = 200)
    {
        $token = $user->createToken('mcare-web')->plainTextToken;

        // Single funnel for password, OTP, invite, Google, and Apple sign-ins,
        // so the account dossier's login trail is complete however they got in.
        $user->recordLogin(request()->ip());

        $payload = [
            'token' => $token,
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile()->exists(),
        ];

        if ($user->role === 'mcare_assistant') {
            $payload['assistant_permissions'] = $user->assistantPermissions()
                ->pluck('permission_key')
                ->all();
        }

        return $this->success($payload, $message, $status);
    }
}
