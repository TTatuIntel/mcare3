<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Mail\PasswordResetMail;
use App\Models\CareProvider;
use App\Models\EmailVerificationCode;
use App\Models\User;
use App\Models\UserInvite;
use App\Services\AccountVerificationService;
use App\Services\NewUserAdminNotifier;
use App\Support\ApiResponse;
use App\Support\AppleIdTokenVerifier;
use App\Support\GoogleIdTokenVerifier;
use App\Support\GoogleOAuth;
use App\Support\MailDispatcher;
use App\Support\SmsSender;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    use ApiResponse;

    public function register(Request $request, AccountVerificationService $verification)
    {
        $data = $request->validate([
            'first_name' => 'required|string|max:100',
            'last_name' => 'required|string|max:100',
            'email' => 'required|email|max:255|unique:users,email',
            'phone' => 'nullable|string|max:30',
            'password' => 'required|string|min:8',
            'role' => 'nullable|in:patient',
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
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
            'email_verified_at' => null,
        ]);
        NewUserAdminNotifier::notify($user);

        $dispatch = $verification->issue($user);

        return $this->authPayload(
            $user,
            $dispatch['delivered']
                ? 'Account created. '.$this->deliverySentence($dispatch)
                : 'Account created, but the verification code could not be delivered. Check the address and tap resend.',
            201,
            [
                'verification_delivery' => $dispatch['delivered'] ? 'accepted' : 'failed',
                'verification' => $dispatch,
            ],
        );
    }

    public function login(Request $request, SmsSender $sms)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'password' => 'required|string',
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
        ]);

        $identifier = trim($data['identifier']);
        $email = strtolower($identifier);
        $phone = $sms->normalize($identifier);

        // Accept common demo aliases from older docs / UI defaults.
        $email = match ($email) {
            'amara.o@example.com' => 'amara.okonkwo@example.com',
            'dr.mensah@example.com' => 'dr.mensah@mcare.health',
            'sarah.a@example.com', 'dr.adeyemi@example.com' => 'dr.adeyemi@mcare.health',
            'assistant@mcare.app' => 'assistant@mcare.health',
            default => $email,
        };

        $user = User::query()
            ->where(function ($q) use ($email, $identifier, $phone) {
                $q->whereRaw('LOWER(email) = ?', [$email])
                    ->orWhere('phone', $identifier)
                    ->when($phone !== null, fn ($query) => $query->orWhere('phone_e164', $phone))
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

            return $this->error('Invalid credentials.', 401);
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
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
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
        if ($resolved instanceof JsonResponse) {
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
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
            'challenge_id' => 'nullable|string|size:48',
        ]);

        if (str_starts_with($data['id_token'], 'mock')) {
            return $this->appleMockSignIn($data);
        }

        $challengeId = (string) ($data['challenge_id'] ?? '');
        $expectedNonceHash = $challengeId !== ''
            ? Cache::pull('apple_auth_nonce:'.$challengeId)
            : null;
        if (! is_string($expectedNonceHash) || $expectedNonceHash === '') {
            return $this->error('Apple sign-in challenge expired. Please try again.', 401);
        }

        $payload = $verifier->verify($data['id_token'], $expectedNonceHash);
        if (! $payload) {
            return $this->error('Invalid or expired Apple sign-in. Please try again.', 401);
        }

        $resolved = $this->resolveAppleUser(
            $payload,
            (bool) ($data['create_account'] ?? false),
            $data['first_name'] ?? null,
            $data['last_name'] ?? null,
        );
        if ($resolved instanceof JsonResponse) {
            return $resolved;
        }

        return $this->authPayload($resolved, 'Signed in with Apple.');
    }

    /** Issues a one-time nonce that binds the Apple authorization to mCare. */
    public function appleChallenge()
    {
        $challengeId = Str::random(48);
        $nonce = Str::random(64);
        Cache::put(
            'apple_auth_nonce:'.$challengeId,
            hash('sha256', $nonce),
            now()->addMinutes(10),
        );

        return $this->success([
            'challenge_id' => $challengeId,
            'nonce' => $nonce,
            'expires_in_seconds' => 600,
        ]);
    }

    /**
     * Starts Google OAuth (full-page redirect — works in Firefox & mobile).
     */
    public function googleRedirect(Request $request)
    {
        $data = $request->validate([
            'return_to' => 'required|url',
            'create_account' => 'sometimes|boolean',
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
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
            $request->boolean('remember'),
            $data['device_name'] ?? null,
        ));
    }

    /**
     * Google OAuth callback — exchanges code, signs user in, redirects to Flutter.
     */
    public function googleCallback(Request $request, GoogleIdTokenVerifier $verifier)
    {
        $state = (string) $request->query('state', '');
        $oauth = $state !== '' ? Cache::pull("google_oauth:{$state}") : null;
        $returnTo = is_array($oauth) ? ($oauth['return_to'] ?? '/') : '/';
        $createAccount = is_array($oauth) ? (bool) ($oauth['create_account'] ?? false) : false;
        $remember = is_array($oauth) ? (bool) ($oauth['remember'] ?? false) : false;
        $deviceName = is_array($oauth) ? ($oauth['device_name'] ?? null) : null;

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
        if ($user instanceof JsonResponse) {
            $body = $user->getData(true);
            $message = is_array($body) ? ($body['message'] ?? 'Sign-in failed.') : 'Sign-in failed.';

            return redirect($this->googleReturnUrl($returnTo, ['error' => $message]));
        }

        $issued = $this->issueToken($user, $remember, $deviceName);
        $user->recordLogin($request->ip());

        return redirect($this->googleReturnUrl($returnTo, [
            'token' => $issued['token'],
            'expires_at' => $issued['expires_at'],
            'remember' => $remember,
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile()->exists(),
        ]));
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function resolveGoogleUser(array $payload, bool $createAccount): User|JsonResponse
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
            $user = User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $firstName,
                'last_name' => $lastName,
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'google_id' => $googleId,
                'email_verified_at' => now(),
            ]);
            NewUserAdminNotifier::notify($user);

            return $user;
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
    /**
     * Guards the demo sign-in path used by the Flutter account picker.
     *
     * A "mock" id_token is accepted without verifying anything, so possession
     * of an email address would otherwise be enough to mint a session for that
     * account. It is therefore disabled outside local development, and even
     * there it may only ever sign in a patient — never a doctor, assistant, or
     * admin. Returns null when the request may proceed.
     */
    private function denyMockSignIn(string $provider, ?User $user)
    {
        if (! config('mcare.allow_mock_social_login')) {
            return $this->error(
                'Invalid or expired '.$provider.' sign-in. Please try again.',
                401,
            );
        }

        if ($user && $user->role !== 'patient') {
            return $this->error(
                'Staff accounts must sign in with their mCare credentials.',
                403,
            );
        }

        return null;
    }

    private function googleMockSignIn(array $data)
    {
        $email = strtolower($data['email'] ?? '');
        if ($email === '') {
            return $this->error('Email is required for mock Google sign-in.', 422);
        }

        $user = User::query()->where('email', $email)->first();

        if ($denied = $this->denyMockSignIn('Google', $user)) {
            return $denied;
        }

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
            NewUserAdminNotifier::notify($user);
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
    ): User|JsonResponse {
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

            $user = User::create([
                'unique_id' => User::generateUniqueId(),
                'first_name' => $firstName ?: 'Patient',
                'last_name' => $lastName ?: '',
                'email' => $email,
                'role' => 'patient',
                'approval_status' => 'active',
                'apple_id' => $appleId,
                'email_verified_at' => now(),
            ]);
            NewUserAdminNotifier::notify($user);

            return $user;
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

        if ($denied = $this->denyMockSignIn('Apple', $user)) {
            return $denied;
        }

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
            NewUserAdminNotifier::notify($user);
        } elseif (! $user->apple_id) {
            $user->update(['apple_id' => 'mock:'.$email]);
        }

        return $this->authPayload($user, 'Signed in with Apple (mock).');
    }

    /**
     * Step 1 of account recovery. `channel` picks how the secret travels:
     * `email` sends a single-use reset link/token, `sms` sends a 6-digit OTP
     * to the submitted phone. Omitted, it is inferred from the identifier.
     *
     * The response never reveals whether the account exists, but it does echo
     * the channel and a masked destination so the UI can say where to look.
     */
    public function forgotPassword(Request $request, SmsSender $sms)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'channel' => 'nullable|string|in:email,sms',
        ]);

        $identifier = trim($data['identifier']);
        $looksLikePhone = ! str_contains($identifier, '@')
            && preg_match('/^[\d\s()+.-]{7,}$/', $identifier) === 1;

        $channel = $data['channel'] ?? ($looksLikePhone ? 'sms' : 'email');

        // Each recovery channel only accepts its own identifier type. This
        // keeps the response indistinguishable for known and unknown accounts:
        // an email can never make the API disclose a masked account phone.
        $user = $channel === 'sms'
            ? $this->uniqueUserForPhone($identifier, $sms)
            : (filter_var($identifier, FILTER_VALIDATE_EMAIL)
                ? User::query()->whereRaw('LOWER(email) = ?', [strtolower($identifier)])->first()
                : null);

        // Always report success to avoid account enumeration. The masked
        // destination is derived from the *submitted* identifier when no
        // account matched, so the shape of the reply is identical either way.
        if ($user) {
            $channel === 'sms'
                ? $this->sendResetOtp($user, $sms)
                : $this->sendResetLink($user);
        }

        $destination = $channel === 'sms'
            ? $sms->mask($identifier)
            : $this->maskEmail($identifier);

        $minutes = $channel === 'sms'
            ? (int) config('mcare.auth.reset_otp_minutes', 10)
            : (int) config('mcare.auth.reset_token_minutes', 60);

        return $this->success([
            'channel' => $channel,
            'destination' => $destination,
            'expires_in_minutes' => $minutes,
        ], $channel === 'sms'
            ? 'If an account exists, a verification code was sent by SMS.'
            : 'If an account exists, reset instructions were sent by email.');
    }

    /**
     * Step 2 of the SMS branch: trade a valid OTP for a real reset token, so
     * the final password write goes through the same single endpoint as the
     * emailed link. The OTP is burned here; the token it mints is short-lived.
     */
    public function verifyResetOtp(Request $request, SmsSender $sms)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'code' => 'required|string|size:6',
        ]);

        $identifier = trim($data['identifier']);
        $user = $this->uniqueUserForPhone($identifier, $sms);

        if (! $user) {
            return $this->error('Invalid or expired verification code.', 422);
        }

        $record = EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'password_reset')
            ->orderByDesc('created_at')
            ->first();

        $matches = $record && $record->isValid() && Hash::check($data['code'], $record->code);

        if (! $matches) {
            if ($record && $record->isValid()) {
                $record->increment('attempts');
                if ((int) $record->fresh()->attempts >= 5) {
                    $record->update(['used_at' => now()]);
                }
            }

            return $this->error('Invalid or expired verification code.', 422);
        }

        $record->update(['used_at' => now()]);

        $token = Str::random(64);
        DB::table('password_reset_tokens')->updateOrInsert(
            ['email' => $user->email],
            ['token' => Hash::make($token), 'created_at' => now()],
        );

        return $this->success([
            'email' => $user->email,
            'token' => $token,
        ], 'Code verified. Choose a new password.');
    }

    /**
     * Step 3. Accepts the emailed token or the one minted by verifyResetOtp;
     * both are single-use and expire after `mcare.auth.reset_token_minutes`.
     * A successful reset also revokes every existing session, so a stolen
     * device cannot outlive the password it was signed in with.
     */
    public function resetPassword(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'token' => 'required|string',
            'password' => 'required|string|min:8',
        ]);

        $email = strtolower(trim($data['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();
        $row = DB::table('password_reset_tokens')->where('email', $email)->first();
        $linkMatches = $row && Hash::check($data['token'], $row->token);
        $emailCode = null;
        $codeMatches = false;

        if ($user && preg_match('/^\d{6}$/', $data['token']) === 1) {
            $emailCode = EmailVerificationCode::query()
                ->where('user_id', $user->id)
                ->where('purpose', 'password_reset_email')
                ->orderByDesc('created_at')
                ->first();
            $codeMatches = $emailCode
                && $emailCode->isValid()
                && Hash::check($data['token'], $emailCode->code);
        }

        if (! $linkMatches && ! $codeMatches) {
            if ($emailCode && $emailCode->isValid()) {
                $emailCode->increment('attempts');
                if ((int) $emailCode->fresh()->attempts >= 5) {
                    $emailCode->update(['used_at' => now()]);
                }
            }

            return $this->error('Invalid or expired reset token.', 422);
        }

        if ($linkMatches) {
            $ttl = max(5, (int) config('mcare.auth.reset_token_minutes', 60));
            $issuedAt = $row->created_at ? Carbon::parse($row->created_at) : null;
            if ($issuedAt === null || $issuedAt->addMinutes($ttl)->isPast()) {
                DB::table('password_reset_tokens')->where('email', $email)->delete();

                return $this->error('This reset link has expired. Request a new one.', 422);
            }
        }

        $user->update([
            'password' => $data['password'],
            'must_change_password' => false,
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ]);

        DB::table('password_reset_tokens')->where('email', $email)->delete();
        EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'password_reset_email')
            ->whereNull('used_at')
            ->update(['used_at' => now()]);
        $user->tokens()->delete();
        $user->fcmTokens()->delete();

        return $this->success(null, 'Password updated. You can sign in now.');
    }

    public function verifyOtp(Request $request, AccountVerificationService $verification)
    {
        $data = $request->validate([
            'identifier' => 'required|string',
            'code' => 'required|string|size:6',
            'purpose' => 'nullable|string|in:email_verify,login',
            'remember' => 'sometimes|boolean',
            'device_name' => 'sometimes|nullable|string|max:120',
        ]);

        $user = User::query()
            ->where('email', strtolower(trim($data['identifier'])))
            ->orWhere('phone', trim($data['identifier']))
            ->first();

        if (! $user) {
            return $this->error('Invalid verification code.', 422);
        }

        if (! $verification->verifyCode($user, $data['code'])) {
            return $this->error('Invalid or expired verification code.', 422);
        }

        return $this->authPayload($user->fresh(), 'Verified successfully.');
    }

    /**
     * The emailed link, opened in whatever browser the inbox lives in.
     *
     * Public and GET on purpose: it has to work from a mail client on a device
     * that has never signed in, so it cannot require a session, and mail
     * clients only ever issue a GET. The token is the whole credential, which
     * is why it is single-use, short-lived, and stored only as a hash.
     */
    public function verifyEmailLink(string $token, AccountVerificationService $verification)
    {
        $user = $verification->consumeLink($token);
        $frontend = rtrim((string) config('mcare.frontend_url'), '/');

        // A link is followed by a human in a browser, so the answer is a page,
        // not JSON. The app reads the status off the query string and says
        // either "you are verified, sign in" or "ask for a fresh link".
        $status = $user ? 'verified' : 'invalid';
        $query = ['status' => $status];
        if ($user) {
            $query['email'] = $user->email;
        }

        return redirect()->away($frontend.'/verify-email?'.http_build_query($query));
    }

    public function resendOtp(Request $request, AccountVerificationService $verification)
    {
        $data = $request->validate([
            'identifier' => 'sometimes|string',
            'purpose' => 'nullable|string|in:email_verify',
            // Which way to send it. Omitted means every channel the account
            // has — the patient who asks again usually wants both.
            'channel' => 'nullable|string|in:email,sms,all',
        ]);

        /** @var User $user */
        $user = $request->user();
        if ($user->email_verified_at !== null) {
            return $this->success(
                [
                    'verification_delivery' => 'not_required',
                    'verification' => $verification->status($user),
                ],
                'This email address is already verified.',
            );
        }

        $channel = $data['channel'] ?? 'all';
        if ($channel === 'sms' && ! filled($user->phone)) {
            return $this->error(
                'There is no phone number on this account to send a code to.',
                422,
                ['verification' => $verification->status($user)],
            );
        }

        $dispatch = $verification->issue(
            $user,
            $channel === 'all' ? null : [$channel],
        );

        if (! $dispatch['delivered']) {
            return $this->error(
                $channel === 'sms'
                    ? 'The verification SMS could not be delivered. Check the number or try email instead.'
                    : 'The verification email could not be delivered. Check the address or try again shortly.',
                502,
                [
                    'verification_delivery' => 'failed',
                    'verification' => $dispatch,
                ],
            );
        }

        return $this->success(
            [
                'verification_delivery' => 'accepted',
                'verification' => $dispatch,
            ],
            $this->deliverySentence($dispatch),
        );
    }

    /** Says where the code actually went, in the words a waiting person needs. */
    private function deliverySentence(array $dispatch): string
    {
        $channels = $dispatch['channels'] ?? [];
        $email = $dispatch['email'] ?? 'your email';
        $phone = $dispatch['phone'] ?? 'your phone';

        if (in_array('email', $channels, true) && in_array('sms', $channels, true)) {
            return "We sent a code to {$email} and texted it to {$phone}.";
        }
        if (in_array('sms', $channels, true)) {
            return "We texted a code to {$phone}.";
        }
        if (in_array('email', $channels, true)) {
            return "We sent a code and a verification link to {$email}.";
        }

        return 'The verification code could not be delivered.';
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

    public function sessions(Request $request)
    {
        $currentId = $request->user()->currentAccessToken()?->id;
        $sessions = $request->user()->tokens()
            ->orderByDesc('last_used_at')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($token) => [
                'id' => (string) $token->id,
                'name' => $token->name,
                'current' => (int) $token->id === (int) $currentId,
                'created_at' => $token->created_at?->toIso8601String(),
                'last_used_at' => $token->last_used_at?->toIso8601String(),
                'expires_at' => $token->expires_at?->toIso8601String(),
            ])
            ->values();

        return $this->success(['sessions' => $sessions]);
    }

    public function revokeSession(Request $request, int $tokenId)
    {
        $token = $request->user()->tokens()->whereKey($tokenId)->first();
        if (! $token) {
            return $this->error('Session not found.', 404);
        }

        $current = (int) $request->user()->currentAccessToken()?->id === $tokenId;
        $token->delete();

        return $this->success(['current_session_revoked' => $current], 'Session revoked.');
    }

    public function logoutOtherSessions(Request $request)
    {
        $data = $request->validate(['current_password' => 'required|string']);
        $user = $request->user();
        if (! $user->password || ! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['Current password is incorrect.'],
            ]);
        }

        $currentId = $user->currentAccessToken()?->id;
        $user->tokens()->when($currentId, fn ($query) => $query->where('id', '!=', $currentId))->delete();

        return $this->success(null, 'Other sessions signed out.');
    }

    public function updateProfile(Request $request)
    {
        $data = $request->validate([
            'first_name' => 'required|string|max:80',
            'last_name' => 'required|string|max:80',
            'phone' => 'required|string|max:30',
            'specialty' => 'nullable|string|max:120',
            'license_number' => 'nullable|string|max:80',
        ]);

        $user = $request->user();

        $updates = [
            'first_name' => $data['first_name'],
            'last_name' => $data['last_name'],
            'phone' => $data['phone'],
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
        if ($user->role === 'doctor') {
            CareProvider::resolveForUser($user->id);
        }

        return $this->success(['user' => $user->fresh()->toApiArray()], 'Profile updated.');
    }

    public function changeEmail(Request $request, AccountVerificationService $verification)
    {
        $data = $request->validate([
            'current_password' => 'required|string',
            'new_email' => 'required|email|max:255',
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

        // The new address is unproven, so it is verified the same way the
        // first one was — by email only. Texting the code to a phone that is
        // still attached to the old, proven address would let someone who has
        // the handset confirm an address the account holder never chose.
        $dispatch = $verification->issue($user->fresh(), ['email']);

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
            'verification_delivery' => $dispatch['delivered'] ? 'accepted' : 'failed',
            'verification' => $dispatch,
        ], $dispatch['delivered']
            ? 'Email updated. '.$this->deliverySentence($dispatch)
            : 'Email updated, but the verification message could not be delivered. Check the address and tap resend.');
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
        $user->fcmTokens()->delete();

        return $this->success([
            'user' => $user->fresh()->toApiArray(),
        ], 'Password updated.');
    }

    private function authPayload(
        User $user,
        string $message,
        int $status = 200,
        array $extra = [],
    ) {
        $remember = request()->boolean('remember');
        $issued = $this->issueToken(
            $user,
            $remember,
            request()->input('device_name'),
        );

        // Single funnel for password, OTP, invite, Google, and Apple sign-ins,
        // so the account dossier's login trail is complete however they got in.
        $user->recordLogin(request()->ip());

        $payload = [
            'token' => $issued['token'],
            'expires_at' => $issued['expires_at'],
            'remember' => $remember,
            'user' => $user->toApiArray(),
            'has_health_profile' => $user->healthProfile()->exists(),
        ] + $extra;

        if ($user->role === 'mcare_assistant') {
            $payload['assistant_permissions'] = $user->assistantPermissions()
                ->pluck('permission_key')
                ->all();
        }

        return $this->success($payload, $message, $status);
    }

    /** @return array{token: string, expires_at: string} */
    private function issueToken(User $user, bool $remember, mixed $deviceName = null): array
    {
        $minutes = max(5, (int) config(
            $remember ? 'mcare.auth.remember_token_minutes' : 'mcare.auth.session_token_minutes',
            $remember ? 43200 : 480,
        ));
        $expiresAt = now()->addMinutes($minutes);
        $name = trim((string) $deviceName);
        if ($name === '') {
            $name = 'mCare '.(request()->userAgent() ?: 'device');
        }
        $name = Str::limit($name, 120, '');

        $created = $user->createToken($name, ['*'], $expiresAt);

        $maximum = max(1, (int) config('mcare.auth.max_device_sessions', 10));
        $user->tokens()
            ->where('id', '!=', $created->accessToken->id)
            ->orderByDesc('last_used_at')
            ->orderByDesc('created_at')
            ->skip($maximum - 1)
            ->take(100)
            ->get()
            ->each->delete();

        return [
            'token' => $created->plainTextToken,
            'expires_at' => $expiresAt->toIso8601String(),
        ];
    }

    /** Emails a single-use reset token plus a deep link into the reset screen. */
    private function sendResetLink(User $user): bool
    {
        $token = Str::random(64);
        $plainCode = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $minutes = max(5, (int) config('mcare.auth.reset_token_minutes', 60));
        DB::table('password_reset_tokens')->updateOrInsert(
            ['email' => $user->email],
            ['token' => Hash::make($token), 'created_at' => now()],
        );

        EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'password_reset_email')
            ->whereNull('used_at')
            ->update(['used_at' => now()]);
        EmailVerificationCode::create([
            'user_id' => $user->id,
            'code' => Hash::make($plainCode),
            'purpose' => 'password_reset_email',
            'expires_at' => now()->addMinutes($minutes),
            'attempts' => 0,
        ]);

        return MailDispatcher::send(
            $user->email,
            new PasswordResetMail(
                $user,
                $token,
                config('mcare.frontend_url'),
                $plainCode,
                $minutes,
            ),
            ['purpose' => 'password_reset'],
        );
    }

    /**
     * Texts a 6-digit reset OTP. Stored hashed and one-at-a-time: any earlier
     * unused password_reset code is burned first so only the newest works.
     */
    private function sendResetOtp(User $user, SmsSender $sms): void
    {
        $plainCode = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'password_reset')
            ->whereNull('used_at')
            ->update(['used_at' => now()]);

        EmailVerificationCode::create([
            'user_id' => $user->id,
            'code' => Hash::make($plainCode),
            'purpose' => 'password_reset',
            'expires_at' => now()->addMinutes(max(2, (int) config('mcare.auth.reset_otp_minutes', 10))),
            'attempts' => 0,
        ]);

        $minutes = max(2, (int) config('mcare.auth.reset_otp_minutes', 10));
        $sms->send(
            (string) $user->phone,
            "Your mCare password reset code is {$plainCode}. It expires in {$minutes} minutes. If you did not request this, ignore this message.",
        );
    }

    /** j••••e@example.com — enough to recognise the inbox, not to learn it. */
    private function maskEmail(string $email): string
    {
        $email = trim($email);
        $at = strpos($email, '@');
        if ($at === false || $at === 0) {
            return $email === '' ? '' : str_repeat('•', strlen($email));
        }

        $name = substr($email, 0, $at);
        $domain = substr($email, $at);
        if (strlen($name) <= 2) {
            return str_repeat('•', strlen($name)).$domain;
        }

        return $name[0].str_repeat('•', strlen($name) - 2).$name[strlen($name) - 1].$domain;
    }

    /**
     * Resolves a phone only when it belongs to exactly one account. Shared or
     * duplicate household numbers intentionally cannot reset a password.
     */
    private function uniqueUserForPhone(string $identifier, SmsSender $sms): ?User
    {
        $normalized = $sms->normalize($identifier);
        if ($normalized === null) {
            return null;
        }

        $matches = User::query()
            ->where('phone', $identifier)
            ->orWhere('phone_e164', $normalized)
            ->limit(2)
            ->get();

        return $matches->count() === 1 ? $matches->first() : null;
    }
}
