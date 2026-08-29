@php($ttl = max(5, (int) config('mcare.auth.reset_token_minutes', 60)))
Hello {{ $user->first_name }},

We received a request to reset your mCare password.

Open this link to choose a new password:
{{ $frontendUrl }}/reset-password?email={{ urlencode($user->email) }}&token={{ urlencode($resetToken) }}

Or open the mCare app (Forgot password → I have a reset code) and enter:
- Email: {{ $user->email }}
- Reset token: {{ $resetToken }}

This link can be used once and expires in {{ $ttl }} minutes. Resetting your password signs you out on every device.

If you did not request this, you can ignore this email — your password stays unchanged. An admin can also issue a temporary password from Users & passwords.

— mCare
