Hello {{ $patient->first_name }},

mCare staff have asked to prepare a report from your health record for:
{{ $reportRequest->purpose }}

@if ($reportRequest->recipient)
It would be shared with: {{ $reportRequest->recipient }}

@endif
The report would include ONLY these parts of your record:
@foreach ($sectionLabels as $label)
  - {{ $label }}
@endforeach

Nothing is shared unless you approve it.

Your one-time approval code is:

{{ $code }}

You can either read this code back to the mCare staff member who called you,
or sign in and approve it yourself under "Sharing requests":

{{ $approvalUrl }}

For your safety this link asks you to sign in first — nobody can approve
sharing of your record just by opening your email.

This code expires at {{ $reportRequest->consent_expires_at?->format('d M Y, H:i') }}.
If you did not expect this request, ignore this email and contact mCare support.

— mCare
