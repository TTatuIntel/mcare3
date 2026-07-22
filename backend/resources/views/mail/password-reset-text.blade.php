Hello {{ $user->first_name }},

We received a request to reset your mCare password.

Open the mCare app (Forgot password → Reset password) and enter:
- Email: {{ $user->email }}
- Reset token: {{ $resetToken }}

Or open this link if your client supports deep links:
{{ $frontendUrl }}/reset-password?email={{ urlencode($user->email) }}&token={{ urlencode($resetToken) }}

If you did not request this, you can ignore this email. An admin can also issue a temporary password from Users & passwords.

— mCare
