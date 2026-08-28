Hello {{ $user->first_name }},

@if ($approved)
Your application to join mCare as {{ $user->roleToClient() }} has been approved.

Sign in with the details below to finish setting up your account.
@else
An mCare administrator has reset the password on your account.

Sign in with the details below to choose a new one.
@endif

Email: {{ $user->email }}
Temporary password: {{ $temporaryPassword }}

You will be asked to choose your own password as soon as you sign in. This
temporary one stops working at that point, so it cannot be reused.

App link: {{ $frontendUrl }}

If you did not expect this email, contact your mCare administrator — do not
share the password above with anyone.

— mCare
