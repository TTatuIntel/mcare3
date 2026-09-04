{{--
  The one HTML email template for the whole application.

  Every mailable renders through this file by handing it a block list built
  with App\Support\MailContent. Nothing here knows what a password reset or a
  consent request is — it knows how to draw a paragraph, a one-time code, a
  button, a fact table, a callout. Restyling mCare's mail is editing this file.

  Constraints this markup deliberately respects:
    * tables for layout, because Outlook still renders through Word,
    * styles inlined on the elements, because Gmail strips much of <style>,
    * no remote images, because most clients block them by default and an OTP
      must be readable before the reader clicks "show images",
    * a hidden preheader, so inbox previews say something useful,
    * a dark-mode block for the clients that honour prefers-color-scheme.
--}}
@php
    // Tone palette shared by callouts and buttons — matches the Flutter app.
    $tones = [
        'info' => ['solid' => '#6366F1', 'soft' => '#EEF2FF', 'edge' => '#C7D2FE', 'text' => '#3730A3'],
        'success' => ['solid' => '#059669', 'soft' => '#ECFDF5', 'edge' => '#A7F3D0', 'text' => '#065F46'],
        'warning' => ['solid' => '#D97706', 'soft' => '#FFFBEB', 'edge' => '#FDE68A', 'text' => '#92400E'],
        'danger' => ['solid' => '#DC2626', 'soft' => '#FEF2F2', 'edge' => '#FECACA', 'text' => '#991B1B'],
    ];
    $tone = fn (?string $key) => $tones[$key ?? 'info'] ?? $tones['info'];

    $ink = '#0F172A';
    $muted = '#64748B';
    $faint = '#94A3B8';
    $border = '#E2E8F0';
    $surface = '#FFFFFF';
    $surfaceAlt = '#F8FAFC';
    $page = '#F1F5F9';
    $brand = '#6366F1';

    $font = 'margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;';
    $para = $font.'font-size:16px;line-height:1.6;color:'.$ink.';';
@endphp
<div style="background-color:{{ $page }};margin:0;padding:0;width:100%;">
<style>
    /* Clients that ignore this still get the inline styles below. */
    @media only screen and (max-width:620px) {
        .mc-shell { width:100% !important; }
        .mc-pad { padding-left:24px !important; padding-right:24px !important; }
        .mc-code { font-size:30px !important; letter-spacing:6px !important; }
        .mc-btn a { display:block !important; }
        .mc-fact-label, .mc-fact-value { display:block !important; width:100% !important; }
        .mc-fact-value { padding-top:0 !important; }
    }
    @media (prefers-color-scheme: dark) {
        .mc-page { background-color:#0B1120 !important; }
        .mc-card { background-color:#111827 !important; border-color:#1F2937 !important; }
        .mc-ink, .mc-ink * { color:#F1F5F9 !important; }
        .mc-muted, .mc-muted * { color:#94A3B8 !important; }
        .mc-alt { background-color:#0F172A !important; border-color:#1F2937 !important; }
        .mc-rule { border-color:#1F2937 !important; }
    }
</style>

{{-- Inbox preview text, padded so clients do not top it up with body copy. --}}
<div style="display:none;font-size:1px;color:{{ $page }};line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">
    {{ $preheader }}{!! str_repeat('&#8204;&nbsp;', 60) !!}
</div>

<table role="presentation" class="mc-page" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:{{ $page }};border-collapse:collapse;">
<tr><td align="center" style="padding:32px 12px;">

    <table role="presentation" class="mc-shell" cellpadding="0" cellspacing="0" border="0" width="600" style="width:600px;max-width:600px;border-collapse:collapse;">

        {{-- Wordmark as text, not an image, so it survives blocked-image inboxes. --}}
        <tr>
            <td class="mc-pad" style="padding:0 40px 16px;">
                <span style="{{ $font }}font-size:24px;font-weight:700;letter-spacing:-0.5px;color:{{ $brand }};">m</span><span class="mc-ink" style="{{ $font }}font-size:24px;font-weight:700;letter-spacing:-0.5px;color:{{ $ink }};">Care</span>
            </td>
        </tr>

        <tr>
            <td class="mc-card" style="background-color:{{ $surface }};border:1px solid {{ $border }};border-radius:16px;">
                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">

                    <tr>
                        <td class="mc-pad" style="padding:36px 40px 0;">
                            @if ($eyebrow !== '')
                                <p class="mc-muted" style="{{ $font }}margin:0 0 10px;font-size:12px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:{{ $muted }};">{{ $eyebrow }}</p>
                            @endif
                            @if ($heading !== '')
                                <h1 class="mc-ink" style="{{ $font }}margin:0;font-size:26px;line-height:1.25;font-weight:700;letter-spacing:-0.4px;color:{{ $ink }};">{{ $heading }}</h1>
                            @endif
                            @if ($greeting)
                                <p class="mc-ink" style="{{ $para }}margin:20px 0 0;">{{ $greeting }}</p>
                            @endif
                        </td>
                    </tr>

                    @foreach ($blocks as $block)
                        <tr>
                            <td class="mc-pad" style="padding:{{ $block['type'] === 'divider' ? '24px 40px' : '16px 40px 0' }};">
                                @switch ($block['type'])

                                    @case ('paragraph')
                                        <p class="mc-ink" style="{{ $para }}margin:0;">{!! nl2br(e($block['text'])) !!}</p>
                                        @break

                                    @case ('subheading')
                                        <h2 class="mc-ink" style="{{ $font }}margin:12px 0 0;font-size:17px;font-weight:700;line-height:1.35;color:{{ $ink }};">{{ $block['text'] }}</h2>
                                        @break

                                    @case ('code')
                                        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
                                            <tr>
                                                <td class="mc-alt" align="center" style="background-color:{{ $surfaceAlt }};border:1px solid {{ $border }};border-radius:12px;padding:22px 16px;">
                                                    @if (! empty($block['caption']))
                                                        <p class="mc-muted" style="{{ $font }}margin:0 0 10px;font-size:12px;font-weight:600;letter-spacing:0.8px;text-transform:uppercase;color:{{ $muted }};">{{ $block['caption'] }}</p>
                                                    @endif
                                                    <div class="mc-code mc-ink" style="{{ $font }}font-family:Menlo,Consolas,'Liberation Mono',monospace;font-size:34px;font-weight:700;letter-spacing:10px;line-height:1.2;color:{{ $ink }};word-break:break-all;">{{ $block['value'] }}</div>
                                                </td>
                                            </tr>
                                        </table>
                                        @break

                                    @case ('button')
                                        @php ($t = $tone($block['tone'] ?? null))
                                        <table role="presentation" class="mc-btn" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                                            <tr>
                                                <td align="center" bgcolor="{{ $t['solid'] }}" style="background-color:{{ $t['solid'] }};border-radius:10px;">
                                                    <a href="{{ $block['url'] }}" target="_blank" rel="noopener" style="{{ $font }}display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;line-height:1;color:#FFFFFF;text-decoration:none;border-radius:10px;">{{ $block['label'] }}</a>
                                                </td>
                                            </tr>
                                        </table>
                                        <p class="mc-muted" style="{{ $font }}margin:14px 0 0;font-size:13px;line-height:1.5;color:{{ $muted }};">
                                            Button not working? Copy this link into your browser:<br>
                                            <a href="{{ $block['url'] }}" target="_blank" rel="noopener" style="color:{{ $brand }};word-break:break-all;">{{ $block['url'] }}</a>
                                        </p>
                                        @break

                                    @case ('facts')
                                        @if (! empty($block['title']))
                                            <p class="mc-muted" style="{{ $font }}margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:{{ $muted }};">{{ $block['title'] }}</p>
                                        @endif
                                        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" class="mc-alt" style="border-collapse:collapse;background-color:{{ $surfaceAlt }};border:1px solid {{ $border }};border-radius:12px;">
                                            @foreach ($block['rows'] as $label => $value)
                                                <tr>
                                                    <td class="mc-fact-label mc-muted" width="38%" style="{{ $font }}padding:12px 8px 12px 18px;font-size:14px;line-height:1.5;color:{{ $muted }};vertical-align:top;{{ $loop->last ? '' : 'border-bottom:1px solid '.$border.';' }}">{{ $label }}</td>
                                                    <td class="mc-fact-value mc-ink" style="{{ $font }}padding:12px 18px 12px 8px;font-size:14px;line-height:1.5;font-weight:600;color:{{ $ink }};vertical-align:top;word-break:break-word;{{ $loop->last ? '' : 'border-bottom:1px solid '.$border.';' }}">{{ $value }}</td>
                                                </tr>
                                            @endforeach
                                        </table>
                                        @break

                                    @case ('bullets')
                                        @if (! empty($block['title']))
                                            <p class="mc-muted" style="{{ $font }}margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:{{ $muted }};">{{ $block['title'] }}</p>
                                        @endif
                                        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
                                            @foreach ($block['items'] as $item)
                                                <tr>
                                                    <td width="18" style="{{ $para }}padding:3px 0;color:{{ $brand }};vertical-align:top;">&bull;</td>
                                                    <td class="mc-ink" style="{{ $para }}padding:3px 0;">{{ $item }}</td>
                                                </tr>
                                            @endforeach
                                        </table>
                                        @break

                                    @case ('callout')
                                        @php ($t = $tone($block['tone'] ?? null))
                                        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
                                            <tr>
                                                <td style="background-color:{{ $t['soft'] }};border:1px solid {{ $t['edge'] }};border-left:4px solid {{ $t['solid'] }};border-radius:10px;padding:14px 18px;">
                                                    @if (! empty($block['title']))
                                                        <p style="{{ $font }}margin:0 0 4px;font-size:14px;font-weight:700;color:{{ $t['text'] }};">{{ $block['title'] }}</p>
                                                    @endif
                                                    <p style="{{ $font }}margin:0;font-size:14px;line-height:1.6;color:{{ $t['text'] }};">{!! nl2br(e($block['text'])) !!}</p>
                                                </td>
                                            </tr>
                                        </table>
                                        @break

                                    @case ('quote')
                                        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
                                            <tr>
                                                <td class="mc-alt" style="background-color:{{ $surfaceAlt }};border-left:4px solid {{ $border }};border-radius:0 10px 10px 0;padding:14px 18px;">
                                                    <p class="mc-ink" style="{{ $para }}margin:0;font-size:15px;font-style:italic;">{!! nl2br(e($block['text'])) !!}</p>
                                                </td>
                                            </tr>
                                        </table>
                                        @break

                                    @case ('divider')
                                        <hr class="mc-rule" style="border:0;border-top:1px solid {{ $border }};margin:0;height:1px;">
                                        @break

                                @endswitch
                            </td>
                        </tr>
                    @endforeach

                    <tr><td style="height:36px;line-height:36px;font-size:0;">&nbsp;</td></tr>
                </table>
            </td>
        </tr>

        <tr>
            <td class="mc-pad" style="padding:24px 40px 0;">
                @if ($footerNote)
                    <p class="mc-muted" style="{{ $font }}margin:0 0 10px;font-size:12px;line-height:1.6;color:{{ $muted }};">{{ $footerNote }}</p>
                @endif
                <p class="mc-muted" style="{{ $font }}margin:0;font-size:12px;line-height:1.6;color:{{ $faint }};">
                    This is an automated message from {{ $appName }}. Never share a code or password from this email — {{ $appName }} staff will never ask you for one.
                    @if ($supportEmail)
                        <br>Questions? Write to <a href="mailto:{{ $supportEmail }}" style="color:{{ $brand }};">{{ $supportEmail }}</a>.
                    @endif
                    @foreach ($footerLinks as $link)
                        <br><a href="{{ $link['url'] }}" style="color:{{ $brand }};">{{ $link['label'] }}</a>
                    @endforeach
                    <br>&copy; {{ date('Y') }} {{ $appName }}
                </p>
            </td>
        </tr>

    </table>

</td></tr>
</table>
</div>
