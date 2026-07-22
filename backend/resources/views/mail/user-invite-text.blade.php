Hello {{ $user->first_name }},

You've been invited to join mCare as {{ $user->roleToClient() }}.

Open the mCare app and choose "Accept invite", then enter this token:

{{ $inviteToken }}

App link: {{ $frontendUrl }}

This invite expires in 7 days.

— mCare
