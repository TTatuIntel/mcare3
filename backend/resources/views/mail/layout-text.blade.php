{{--
  The plain-text half of every mCare email.

  It walks the same block list as layout.blade.php, so the text part is never
  a stale summary of the HTML — it is the same content, drawn with rules and
  indentation instead of tables. Text-only clients, screen readers, and the
  spam filters that penalise HTML-only mail all read this.
--}}
@php
    $wrap = fn (string $text, string $indent = '') => rtrim(wordwrap(
        preg_replace("/\r\n|\r/", "\n", $text), 72 - strlen($indent), "\n".$indent, false,
    ));
    $rule = str_repeat('-', 60);
@endphp
@if ($eyebrow !== ''){{ strtoupper($eyebrow) }}

@endif
@if ($heading !== ''){{ $heading }}
{{ str_repeat('=', min(60, strlen($heading))) }}

@endif
@if ($greeting){{ $greeting }}

@endif
@foreach ($blocks as $block)
@switch ($block['type'])
@case ('paragraph'){{ $wrap($block['text']) }}

@break
@case ('subheading'){{ strtoupper($block['text']) }}

@break
@case ('code')
@if (! empty($block['caption'])){{ $block['caption'] }}:
@endif
    {{ $block['value'] }}

@break
@case ('button'){{ $block['label'] }}:
{{ $block['url'] }}

@break
@case ('facts')
@if (! empty($block['title'])){{ strtoupper($block['title']) }}
@endif
@foreach ($block['rows'] as $label => $value)
  {{ $label }}: {{ $value }}
@endforeach

@break
@case ('bullets')
@if (! empty($block['title'])){{ strtoupper($block['title']) }}
@endif
@foreach ($block['items'] as $item)
  - {{ $wrap($item, '    ') }}
@endforeach

@break
@case ('callout')
@if (! empty($block['title']))! {{ strtoupper($block['title']) }}
@endif
{{ $wrap($block['text']) }}

@break
@case ('quote')
{{ $wrap($block['text'], '  ') }}

@break
@case ('divider'){{ $rule }}

@break
@endswitch
@endforeach
{{ $rule }}
@if ($footerNote){{ $wrap($footerNote) }}

@endif
{{ $wrap("This is an automated message from {$appName}. Never share a code or password from this email — {$appName} staff will never ask you for one.") }}
@if ($supportEmail)
Questions? Write to {{ $supportEmail }}
@endif
@foreach ($footerLinks as $link)
{{ $link['label'] }}: {{ $link['url'] }}
@endforeach

(c) {{ date('Y') }} {{ $appName }}
