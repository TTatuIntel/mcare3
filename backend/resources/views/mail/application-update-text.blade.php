Hello {{ $user->first_name }},

@if ($kind === \App\Mail\ApplicationUpdateMail::KIND_REJECTED)
Your application to join mCare as {{ $user->roleToClient() }} has not been
approved.

Reason given:

{{ $message }}

If you believe this was decided in error, reply to this email and an
administrator will look at it again.
@else
An mCare administrator needs more information before your application to join
as {{ $user->roleToClient() }} can be decided.

What is needed:

{{ $message }}

Reply to this email with the details above and your application will continue.
Your account stays open in the meantime — there is nothing else to do.
@endif

App link: {{ $frontendUrl }}

— mCare
