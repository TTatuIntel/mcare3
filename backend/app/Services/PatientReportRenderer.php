<?php

namespace App\Services;

/**
 * Renders a frozen report snapshot into a self-contained, printable document.
 *
 * `PatientReportService::issue()` assembles the report, freezes it into the
 * request's `snapshot` column and tells the patient it went out — but nothing
 * could ever render that snapshot back, so the one person whose record it is
 * could not read what had been disclosed about them. This turns the stored
 * array back into a document.
 *
 * HTML rather than a generated PDF on purpose: the project has no PDF engine,
 * and the print stylesheet below is written to A4 — masthead in colour,
 * repeating table headers, a running footer, no orphaned section titles — so
 * "Save as PDF" in any browser produces the same paginated document. Unlike a
 * rasterised PDF it also stays selectable, searchable and screen-readable.
 *
 * The markup is deliberately dependency-free — one stylesheet, no fonts, no
 * remote assets — so it renders identically saved to disk, mailed on, or
 * opened from a phone with no network. The only script is the print button,
 * which is screen-only and whose absence costs a reader nothing.
 */
final class PatientReportRenderer
{
    private const STATUS_ISSUED = 'issued';

    private const STATUS_DRAFT = 'draft';

    private const STATUS_REVOKED = 'revoked';

    /**
     * @param  array<string, mixed>  $snapshot  Output of PatientReportAssembler.
     * @param  string|null  $watermark  Banner text shown above the document.
     * @param  array{status?: string|null, reference?: string|null}  $options
     */
    public function toHtml(array $snapshot, ?string $watermark = null, array $options = []): string
    {
        $title = $this->text($snapshot['title'] ?? 'Medical report');
        $status = $this->status($options['status'] ?? null, $watermark);
        $reference = $this->reference($snapshot, $options['reference'] ?? null);
        $sections = array_values(array_filter(
            (array) ($snapshot['sections'] ?? []),
            'is_array',
        ));

        $body = $this->masthead($snapshot, $status, $reference)
            .'<div class="body">'
            .($watermark === null ? '' : $this->banner($watermark, $status))
            .$this->provenance($snapshot)
            .$this->contents($sections)
            .$this->sections($sections)
            .$this->signoff($snapshot, $status)
            .'</div>';

        $ghost = $status === self::STATUS_ISSUED
            ? ''
            : '<div class="ghost" aria-hidden="true">'.strtoupper($status).'</div>';

        $footLine = $this->text(
            'mCare · '.($snapshot['title'] ?? 'Medical report')
            .' · '.($snapshot['patient_name'] ?? '')
            .' · '.$reference,
        );

        $css = $this->styles();

        return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{$title}</title>
<style>{$css}</style>
</head>
<body>
<div class="toolbar" role="toolbar">
  <span class="toolbar-ref">{$reference}</span>
  <button type="button" class="btn" onclick="window.print()">Save as PDF / Print</button>
</div>
<article class="sheet">{$ghost}{$body}</article>
<p class="print-foot" aria-hidden="true">{$footLine}</p>
</body>
</html>
HTML;
    }

    // ------------------------------------------------------------------
    // document furniture
    // ------------------------------------------------------------------

    /**
     * Brand band, document type, status and subject — everything a reader
     * needs to know what they are holding before reading a single field.
     *
     * @param  array<string, mixed>  $s
     */
    private function masthead(array $s, string $status, string $reference): string
    {
        $title = $this->text($s['title'] ?? 'Medical report');
        $name = (string) ($s['patient_name'] ?? '');
        $uid = $this->text($s['patient_unique_id'] ?? '');
        $generated = $this->moment($s['generated_at'] ?? null) ?? '—';

        $pill = match ($status) {
            self::STATUS_DRAFT => '<span class="stamp stamp-warn">Draft — not issued</span>',
            self::STATUS_REVOKED => '<span class="stamp stamp-bad">Revoked</span>',
            default => '<span class="stamp stamp-ok">Issued</span>',
        };

        $chips = '<span class="chip"><b>Patient ID</b>'.($uid === '' ? '—' : $uid).'</span>'
            .'<span class="chip"><b>Reference</b>'.$reference.'</span>'
            .'<span class="chip"><b>Generated</b>'.$this->text($generated).'</span>';

        return '<header class="masthead">'
            .'<div class="brandrow">'
            .'<div class="wordmark"><span class="mark">m</span>Care'
            .'<span class="wordmark-sub">Remote patient monitoring</span></div>'
            .'<div class="docmeta"><span class="kicker">Medical report</span>'.$pill.'</div>'
            .'</div>'
            .'<h1>'.$title.'</h1>'
            .'</header>'
            .'<div class="idbar">'
            .'<div class="avatar" aria-hidden="true">'.$this->initials($name).'</div>'
            .'<div class="idtext"><p class="idname">'
            .$this->text($name === '' ? 'Unnamed patient' : $name).'</p>'
            .'<p class="idchips">'.$chips.'</p></div>'
            .'</div>';
    }

    /**
     * Who asked for this, why, who received it, and on what authority. A
     * disclosure the patient cannot trace back is not one they can challenge.
     *
     * Laid out as hairline tiles rather than a two-column table: the table
     * spent 38% of the page width on six short labels and left the rest empty.
     *
     * @param  array<string, mixed>  $s
     */
    private function provenance(array $s): string
    {
        $consent = is_array($s['consent'] ?? null) ? $s['consent'] : [];
        $signature = is_array($s['signature'] ?? null) ? $s['signature'] : [];

        $tiles = [
            'Purpose' => $s['purpose'] ?? null,
            'Released to' => $s['recipient'] ?? null,
            'Prepared by' => $s['prepared_by'] ?? null,
            'Generated' => $this->moment($s['generated_at'] ?? null),
            'Patient consent' => ($consent['required'] ?? false)
                ? $this->consentLine($consent)
                : 'Not required for this report',
            'Clinician signature' => ($signature['required'] ?? false)
                ? $this->signatureLine($signature)
                : 'Not required for this report',
        ];

        $out = '';
        foreach ($tiles as $label => $value) {
            $shown = ($value === null || $value === '') ? 'Not recorded' : $value;
            $out .= '<div class="tile"><span class="tile-k">'.$this->text($label).'</span>'
                .'<span class="tile-v">'.$this->text($shown).'</span></div>';
        }

        return '<section class="pane"><p class="pane-k">About this report</p>'
            .'<div class="tiles">'.$out.'</div></section>';
    }

    /**
     * A one-line index of what this report covers.
     *
     * On a fifteen-section disclosure the recipient's first question is what
     * is in it, and the answer used to be "scroll and find out".
     *
     * @param  list<array<string, mixed>>  $sections
     */
    private function contents(array $sections): string
    {
        if ($sections === []) {
            return '';
        }

        $items = '';
        foreach ($sections as $i => $block) {
            $items .= '<li><span class="idx">'.($i + 1).'</span>'
                .$this->text($block['title'] ?? 'Section')
                .'<em>'.$this->text($this->countLabel($block)).'</em></li>';
        }

        return '<nav class="toc"><p class="toc-k">Contents — '.count($sections)
            .' section'.(count($sections) === 1 ? '' : 's').'</p><ol>'.$items.'</ol></nav>';
    }

    /** @param array<string, mixed> $block */
    private function countLabel(array $block): string
    {
        return match ($block['kind'] ?? 'fields') {
            'table' => count((array) ($block['rows'] ?? [])).' rows',
            'notes' => count((array) ($block['notes'] ?? [])).' notes',
            default => count((array) ($block['rows'] ?? [])).' fields',
        };
    }

    /**
     * Closing authority block. The signature is the reason the document can be
     * relied on, so it is set out at the end where a signature belongs rather
     * than buried as the last row of a metadata table.
     *
     * @param  array<string, mixed>  $s
     */
    private function signoff(array $s, string $status): string
    {
        $signature = is_array($s['signature'] ?? null) ? $s['signature'] : [];
        $required = (bool) ($signature['required'] ?? false);
        $signed = $required && ! empty($signature['signed_at']);

        $line = $signed
            ? $this->text($signature['name'] ?? 'Signing clinician')
            : 'Not signed';
        $when = $signed
            ? 'Signed '.$this->text($this->moment($signature['signed_at'] ?? null) ?? '')
            : ($required
                ? 'Awaiting clinician signature'
                : 'No signature required for this report');
        $note = trim((string) ($signature['note'] ?? ''));

        $warn = match ($status) {
            self::STATUS_DRAFT => 'This copy is a draft and has not been issued.',
            self::STATUS_REVOKED => 'This copy is revoked and must not be relied on.',
            default => null,
        };

        return '<section class="signoff">'
            .'<div class="sig">'
            .'<p class="sig-k">Authorised by</p>'
            .'<p class="sig-name'.($signed ? '' : ' sig-unsigned').'">'.$line.'</p>'
            .'<p class="sig-when">'.$when.'</p>'
            .($note === '' ? '' : '<p class="sig-note">'.$this->text($note).'</p>')
            .'</div>'
            .'<div class="conf">'
            .'<p class="conf-k">Confidential — patient record</p>'
            .'<p>This document was generated by mCare from the patient\'s medical '
            .'record and contains only the sections listed above. Handle it under '
            .'the receiving organisation\'s data protection policy and do not '
            .'forward it beyond the named recipient. If anything here looks wrong, '
            .'contact the care team — do not edit this document.</p>'
            .($warn === null ? '' : '<p class="conf-warn">'.$warn.'</p>')
            .'</div>'
            .'</section>';
    }

    /** @param array<string, mixed> $consent */
    private function consentLine(array $consent): string
    {
        $at = $this->moment($consent['granted_at'] ?? null);
        if ($at === null) {
            return 'Required — not yet given';
        }
        $method = $consent['method'] ?? null;

        return 'Given '.$at.($method ? ' (via '.$method.')' : '');
    }

    /** @param array<string, mixed> $signature */
    private function signatureLine(array $signature): string
    {
        $at = $this->moment($signature['signed_at'] ?? null);
        if ($at === null) {
            return 'Required — not yet signed';
        }
        $name = $signature['name'] ?? null;

        return ($name ? $name.' — ' : '').'signed '.$at;
    }

    // ------------------------------------------------------------------
    // sections
    // ------------------------------------------------------------------

    /** @param list<array<string, mixed>> $sections */
    private function sections(array $sections): string
    {
        if ($sections === []) {
            return '<section class="block"><h2><span class="num">1</span>Contents</h2>'
                .'<p class="empty">No sections were included in this report.</p></section>';
        }

        $out = '';
        foreach ($sections as $i => $block) {
            $out .= '<section class="block">'
                .'<h2><span class="num">'.($i + 1).'</span>'
                .$this->text($block['title'] ?? 'Section')
                .'<em class="count">'.$this->text($this->countLabel($block)).'</em></h2>'
                .match ($block['kind'] ?? 'fields') {
                    'table' => $this->tableBlock($block),
                    'notes' => $this->notesBlock($block),
                    default => $this->fieldsBlock($block),
                }
                .'</section>';
        }

        return $out;
    }

    /**
     * Label/value pairs as a two-column definition grid. Twice the rows of the
     * old full-width table in the same vertical space, and no 38% gutter.
     *
     * @param  array<string, mixed>  $block
     */
    private function fieldsBlock(array $block): string
    {
        $out = '';
        foreach ((array) ($block['rows'] ?? []) as $row) {
            if (! is_array($row)) {
                continue;
            }
            $value = $row['value'] ?? null;
            $shown = ($value === null || $value === '') ? 'Not recorded' : $value;
            // A long value (an address, a conditions list) gets the full width
            // rather than wrapping into a narrow ragged column.
            $long = is_string($shown) && mb_strlen($shown) > 58;
            $out .= '<div class="pair'.($long ? ' wide' : '').'">'
                .'<span class="pair-k">'.$this->text($row['label'] ?? '').'</span>'
                .'<span class="pair-v">'.$this->cell($shown).'</span></div>';
        }

        return $out === ''
            ? $this->empty($block['empty_message'] ?? 'Nothing recorded.')
            : '<div class="pairs">'.$out.'</div>';
    }

    /** @param array<string, mixed> $block */
    private function tableBlock(array $block): string
    {
        $columns = array_values(array_filter(
            (array) ($block['columns'] ?? []),
            'is_scalar',
        ));
        $rows = (array) ($block['rows'] ?? []);

        if ($rows === []) {
            return $this->empty($block['empty_message'] ?? 'Nothing recorded.');
        }

        $head = '';
        foreach ($columns as $column) {
            $head .= '<th>'.$this->text($column).'</th>';
        }

        $body = '';
        foreach ($rows as $row) {
            if (! is_array($row)) {
                continue;
            }
            $body .= '<tr>';
            // Rows arrive as positional lists matching `columns`; padding keeps
            // a short row from silently shifting every cell after it.
            $cells = array_values($row);
            for ($i = 0; $i < max(count($columns), count($cells)); $i++) {
                $value = $cells[$i] ?? '';
                $body .= $i === 0
                    ? '<td class="lead">'.$this->cell($value).'</td>'
                    : '<td>'.$this->cell($value).'</td>';
            }
            $body .= '</tr>';
        }

        return '<div class="tablewrap"><table>'
            ."<thead><tr>{$head}</tr></thead><tbody>{$body}</tbody></table></div>";
    }

    /**
     * Doctor-authored notes. The assembler has emitted these as `kind: notes`
     * since it was written and nothing ever rendered them, so a report that
     * included clinical notes printed "Nothing recorded." over the top of them.
     *
     * @param  array<string, mixed>  $block
     */
    private function notesBlock(array $block): string
    {
        $notes = array_values(array_filter((array) ($block['notes'] ?? []), 'is_array'));
        if ($notes === []) {
            return $this->empty($block['empty_message'] ?? 'No published notes.');
        }

        $out = '';
        foreach ($notes as $note) {
            $body = trim((string) ($note['body'] ?? ''));
            $byline = array_values(array_filter([
                trim((string) ($note['author'] ?? '')),
                trim((string) ($note['at'] ?? '')),
            ], static fn (string $part) => $part !== ''));

            $out .= '<article class="note">'
                .'<p class="note-t">'.$this->text($note['title'] ?? 'Clinical note').'</p>'
                .($byline === [] ? '' : '<p class="note-by">'
                    .$this->text(implode(' · ', $byline)).'</p>')
                .'<div class="note-b">'.($body === ''
                    ? '<span class="na">No content recorded.</span>'
                    : nl2br($this->text($body))).'</div>'
                .'</article>';
        }

        return '<div class="notes">'.$out.'</div>';
    }

    private function empty(mixed $message): string
    {
        return '<p class="empty">'.$this->text($message).'</p>';
    }

    private function banner(string $message, string $status): string
    {
        $tone = $status === self::STATUS_DRAFT ? 'banner-warn' : 'banner-bad';

        return '<p class="banner '.$tone.'">'.$this->text($message).'</p>';
    }

    // ------------------------------------------------------------------
    // cell presentation
    // ------------------------------------------------------------------

    /**
     * Escapes a value and gives the ones that carry meaning a shape: a clinical
     * status becomes a coloured pill, a percentage gets a bar behind it, a
     * trend gets its arrow. Read across a vitals table and the outliers are
     * visible before any of it is read as words.
     */
    private function cell(mixed $value): string
    {
        $text = $this->text($value);
        $plain = trim(is_scalar($value) ? (string) $value : '');

        if ($plain === '' || $plain === '—') {
            return '<span class="na">—</span>';
        }

        if (preg_match('/^(\d{1,3}(?:\.\d+)?)%$/', $plain, $m)) {
            $pct = min(100.0, (float) $m[1]);
            $tone = $pct >= 80 ? 'ok' : ($pct >= 50 ? 'warn' : 'bad');

            return '<span class="meter"><span class="meter-bar meter-'.$tone.'" '
                .'style="width:'.number_format($pct, 0).'%"></span></span>'
                .'<span class="meter-n">'.$text.'</span>';
        }

        $tone = $this->tone($plain);
        if ($tone !== null) {
            return '<span class="pill pill-'.$tone.'">'.$this->glyph($plain).$text.'</span>';
        }

        return $text;
    }

    /** Clinical vocabulary the whole report shares, mapped to one palette. */
    private function tone(string $value): ?string
    {
        return match (mb_strtolower($value)) {
            'normal', 'healthy', 'active', 'followed', 'yes', 'stable', 'completed',
            'approved', 'consented', 'resolved', 'none known', 'none' => 'ok',
            'warning', 'partly', 'overweight', 'underweight', 'pending', 'partial',
            'scheduled', 'not logged' => 'warn',
            'critical', 'obese', 'missed', 'no', 'skipped', 'cancelled', 'revoked',
            'declined', 'not recorded', 'not consented' => 'bad',
            'ended', 'past', 'inactive', 'closed', 'archived' => 'slate',
            'rising', 'falling', 'improving', 'worsening' => 'brand',
            default => null,
        };
    }

    private function glyph(string $value): string
    {
        return match (mb_strtolower($value)) {
            'rising', 'improving' => '<span class="gly">&#9650;</span>',
            'falling', 'worsening' => '<span class="gly">&#9660;</span>',
            'stable' => '<span class="gly">&#9679;</span>',
            'critical' => '<span class="gly">&#9888;</span>',
            default => '',
        };
    }

    private function initials(string $name): string
    {
        $parts = array_values(array_filter(preg_split('/\s+/', trim($name)) ?: []));
        if ($parts === []) {
            return '?';
        }
        $first = mb_substr($parts[0], 0, 1);
        $last = count($parts) > 1 ? mb_substr($parts[count($parts) - 1], 0, 1) : '';

        return $this->text(mb_strtoupper($first.$last));
    }

    /**
     * Callers know the state of the request; the fallback reads it off the
     * banner so an older call site cannot silently stamp a draft as issued.
     */
    private function status(?string $status, ?string $watermark): string
    {
        $status = mb_strtolower(trim((string) $status));
        if (in_array($status, [self::STATUS_ISSUED, self::STATUS_DRAFT, self::STATUS_REVOKED], true)) {
            return $status;
        }
        if ($watermark === null) {
            return self::STATUS_ISSUED;
        }

        return str_contains($watermark, 'DRAFT') ? self::STATUS_DRAFT : self::STATUS_REVOKED;
    }

    /** @param array<string, mixed> $snapshot */
    private function reference(array $snapshot, ?string $reference): string
    {
        $reference = trim((string) $reference);
        if ($reference !== '') {
            return $this->text($reference);
        }

        // No request id in the snapshot: fall back to something stable and
        // quotable — the patient's id and the day it was produced.
        $uid = trim((string) ($snapshot['patient_unique_id'] ?? '')) ?: 'MCARE';
        $day = $this->moment($snapshot['generated_at'] ?? null, 'Ymd') ?? date('Ymd');

        return $this->text($uid.'/'.$day);
    }

    private function moment(mixed $iso, string $format = 'j M Y, H:i'): ?string
    {
        if (! is_string($iso) || $iso === '') {
            return null;
        }
        try {
            return \Carbon\Carbon::parse($iso)->format($format);
        } catch (\Throwable) {
            return $iso;
        }
    }

    /**
     * Everything rendered here came from the patient's own record — free-text
     * notes, medication names, a recipient typed by staff — so every value is
     * escaped. A report is also mailed onward and opened outside the app.
     */
    private function text(mixed $value): string
    {
        if (is_bool($value)) {
            return $value ? 'Yes' : 'No';
        }
        if (is_array($value)) {
            $value = implode(', ', array_filter($value, 'is_scalar'));
        }

        return htmlspecialchars((string) ($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    // ------------------------------------------------------------------
    // stylesheet
    // ------------------------------------------------------------------

    /**
     * One stylesheet, written twice over: once for a screen and once for A4.
     * The palette is the Flutter app's, so a report opened beside the app
     * reads as the same product.
     */
    private function styles(): string
    {
        return <<<'CSS'
:root{
  --ink:#0F172A; --ink2:#1E293B; --muted:#64748B; --faint:#94A3B8;
  --line:#E2E8F0; --line2:#EEF2F7; --alt:#F8FAFC; --page:#EEF1F6;
  --brand:#4F46E5; --brand2:#6366F1; --brand3:#8B5CF6; --brandsoft:#EEF2FF;
  --ok:#047857; --okbg:#ECFDF5; --okedge:#A7F3D0;
  --warn:#B45309; --warnbg:#FFFBEB; --warnedge:#FDE68A;
  --bad:#B91C1C; --badbg:#FEF2F2; --badedge:#FECACA;
  --slate:#475569; --slatebg:#F1F5F9;
  color-scheme:light;
}
*{box-sizing:border-box}
body{
  margin:0; padding:20px 14px 40px; background:var(--page); color:var(--ink);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  font-size:14px; line-height:1.5; -webkit-font-smoothing:antialiased;
}
.sheet{
  position:relative; max-width:940px; margin:0 auto; background:#fff;
  border:1px solid var(--line); border-radius:14px; overflow:hidden;
  box-shadow:0 10px 30px rgba(15,23,42,.08);
}
.body{padding:18px 26px 24px}

/* ---- toolbar (screen only) ------------------------------------------ */
.toolbar{
  max-width:940px; margin:0 auto 12px; display:flex; align-items:center;
  justify-content:space-between; gap:12px;
}
.toolbar-ref{font-size:12px; font-weight:600; letter-spacing:.04em; color:var(--muted)}
.btn{
  font:inherit; font-size:13px; font-weight:600; color:#fff; cursor:pointer;
  background:var(--brand); border:0; border-radius:8px; padding:9px 16px;
  box-shadow:0 1px 2px rgba(15,23,42,.2);
}
.btn:hover{background:#4338CA}

/* ---- masthead -------------------------------------------------------- */
.masthead{
  background:linear-gradient(120deg,#4338CA 0%,var(--brand2) 52%,var(--brand3) 100%);
  color:#fff; padding:18px 26px 20px;
}
.brandrow{display:flex; align-items:flex-start; justify-content:space-between; gap:16px}
.wordmark{font-size:21px; font-weight:800; letter-spacing:-.4px; line-height:1.1}
.wordmark .mark{color:#C7D2FE}
.wordmark-sub{
  display:block; font-size:10px; font-weight:600; letter-spacing:.14em;
  text-transform:uppercase; color:rgba(255,255,255,.72); margin-top:3px;
}
.docmeta{display:flex; flex-direction:column; align-items:flex-end; gap:7px; text-align:right}
.kicker{
  font-size:10px; font-weight:700; letter-spacing:.16em; text-transform:uppercase;
  color:rgba(255,255,255,.78);
}
.stamp{
  display:inline-block; font-size:11px; font-weight:700; letter-spacing:.06em;
  text-transform:uppercase; padding:4px 10px; border-radius:999px; border:1px solid;
}
.stamp-ok{background:#ECFDF5; color:#065F46; border-color:#6EE7B7}
.stamp-warn{background:#FFFBEB; color:#92400E; border-color:#FCD34D}
.stamp-bad{background:#FEF2F2; color:#991B1B; border-color:#FCA5A5}
.masthead h1{
  font-size:24px; line-height:1.2; letter-spacing:-.4px; font-weight:700;
  margin:16px 0 0; max-width:44ch;
}

/* ---- patient identity bar -------------------------------------------- */
.idbar{
  display:flex; align-items:center; gap:13px; padding:12px 26px;
  background:var(--alt); border-bottom:1px solid var(--line);
}
.avatar{
  flex:0 0 auto; width:40px; height:40px; border-radius:11px; display:grid;
  place-items:center; font-size:14px; font-weight:700;
  color:var(--brand); background:var(--brandsoft); border:1px solid #C7D2FE;
}
.idtext{min-width:0}
.idname{margin:0; font-size:16px; font-weight:700; letter-spacing:-.2px}
.idchips{margin:3px 0 0; display:flex; flex-wrap:wrap; gap:4px 14px}
.chip{font-size:11.5px; color:var(--ink2); white-space:nowrap}
.chip b{
  display:inline-block; font-size:9.5px; font-weight:700; letter-spacing:.1em;
  text-transform:uppercase; color:var(--faint); margin-right:5px;
}

/* ---- banner ---------------------------------------------------------- */
.banner{
  margin:0 0 16px; padding:11px 13px; border-radius:9px; font-size:13px;
  font-weight:600; line-height:1.45; border:1px solid;
}
.banner-warn{background:var(--warnbg); border-color:var(--warnedge); color:#92400E}
.banner-bad{background:var(--badbg); border-color:var(--badedge); color:#991B1B}

/* ---- provenance tiles ------------------------------------------------ */
.pane{margin:0 0 16px}
.pane-k,.toc-k{
  margin:0 0 6px; font-size:9.5px; font-weight:700; letter-spacing:.1em;
  text-transform:uppercase; color:var(--muted);
}
.tiles{
  display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:1px;
  background:var(--line); border:1px solid var(--line); border-radius:11px;
  overflow:hidden;
}
.tile{background:#fff; padding:9px 12px; min-width:0}
.tile-k{
  display:block; font-size:9.5px; font-weight:700; letter-spacing:.1em;
  text-transform:uppercase; color:var(--faint); margin-bottom:2px;
}
.tile-v{display:block; font-size:13px; font-weight:600; line-height:1.35}

/* ---- contents -------------------------------------------------------- */
.toc{
  border:1px solid var(--line); border-radius:11px; padding:10px 13px 11px;
  background:var(--alt); margin:0 0 18px;
}
.toc ol{
  list-style:none; margin:0; padding:0; display:grid;
  grid-template-columns:repeat(3,minmax(0,1fr)); gap:4px 16px;
}
.toc li{
  display:flex; align-items:center; gap:7px; font-size:12px; font-weight:600;
  color:var(--ink2); min-width:0;
}
.toc li em{
  font-style:normal; font-weight:500; font-size:10.5px; color:var(--faint);
  margin-left:auto; white-space:nowrap;
}
.idx{
  flex:0 0 auto; width:17px; height:17px; border-radius:5px; display:grid;
  place-items:center; font-size:9.5px; font-weight:700; color:var(--brand);
  background:#fff; border:1px solid #C7D2FE;
}

/* ---- sections -------------------------------------------------------- */
.block{margin:0 0 18px}
.block h2{
  display:flex; align-items:center; gap:9px; margin:0 0 9px; padding-bottom:6px;
  border-bottom:2px solid var(--brandsoft); font-size:12.5px; font-weight:700;
  letter-spacing:.09em; text-transform:uppercase; color:var(--ink2);
}
.block h2 .num{
  flex:0 0 auto; width:20px; height:20px; border-radius:6px; display:grid;
  place-items:center; font-size:10.5px; letter-spacing:0; color:#fff;
  background:linear-gradient(135deg,var(--brand),var(--brand3));
}
.block h2 .count{
  font-style:normal; font-weight:600; font-size:10px; letter-spacing:.06em;
  color:var(--faint); margin-left:auto; text-transform:none;
}

/* ---- field pairs ----------------------------------------------------- */
.pairs{
  display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:0 26px;
  border-top:1px solid var(--line2);
}
.pair{
  display:flex; align-items:baseline; justify-content:space-between; gap:14px;
  padding:6px 0; border-bottom:1px solid var(--line2); min-width:0;
}
.pair.wide{grid-column:1/-1}
.pair-k{font-size:12px; color:var(--muted); flex:0 0 auto; max-width:52%}
.pair-v{
  font-size:13px; font-weight:600; text-align:right; min-width:0;
  overflow-wrap:anywhere;
}

/* ---- tables ---------------------------------------------------------- */
.tablewrap{
  border:1px solid var(--line); border-radius:10px; overflow:hidden;
  overflow-x:auto; -webkit-overflow-scrolling:touch;
}
table{width:100%; border-collapse:collapse; font-size:12.5px}
th{
  text-align:left; padding:7px 10px; background:var(--alt); color:var(--muted);
  font-size:9.5px; font-weight:700; letter-spacing:.09em; text-transform:uppercase;
  border-bottom:1px solid var(--line); white-space:nowrap;
}
td{padding:6px 10px; border-bottom:1px solid var(--line2); vertical-align:top}
tbody tr:nth-child(even) td{background:#FBFCFE}
tbody tr:last-child td{border-bottom:0}
td.lead{font-weight:600; color:var(--ink)}

/* ---- value shapes ---------------------------------------------------- */
.pill{
  display:inline-flex; align-items:center; gap:4px; padding:1px 8px;
  border-radius:999px; font-size:11px; font-weight:700; line-height:1.6;
  border:1px solid; white-space:nowrap;
}
.pill-ok{background:var(--okbg); border-color:var(--okedge); color:var(--ok)}
.pill-warn{background:var(--warnbg); border-color:var(--warnedge); color:var(--warn)}
.pill-bad{background:var(--badbg); border-color:var(--badedge); color:var(--bad)}
.pill-slate{background:var(--slatebg); border-color:var(--line); color:var(--slate)}
.pill-brand{background:var(--brandsoft); border-color:#C7D2FE; color:var(--brand)}
.gly{font-size:9px; line-height:1}
.meter{
  display:inline-block; vertical-align:middle; width:44px; height:6px;
  border-radius:999px; background:var(--line); overflow:hidden; margin-right:6px;
}
.meter-bar{display:block; height:100%; border-radius:999px}
.meter-ok{background:#10B981}
.meter-warn{background:#F59E0B}
.meter-bad{background:#EF4444}
.meter-n{font-variant-numeric:tabular-nums; font-weight:600}
.na{color:var(--faint)}

/* ---- notes ----------------------------------------------------------- */
.notes{display:grid; gap:9px}
.note{
  border:1px solid var(--line); border-left:3px solid var(--brand2);
  border-radius:9px; padding:10px 13px; background:var(--alt);
}
.note-t{margin:0; font-size:13.5px; font-weight:700}
.note-by{margin:1px 0 6px; font-size:11px; color:var(--muted)}
.note-b{font-size:12.5px; line-height:1.55; color:var(--ink2)}

/* ---- empty ----------------------------------------------------------- */
.empty{
  margin:0; padding:11px 13px; border:1px dashed var(--line); border-radius:9px;
  background:var(--alt); color:var(--faint); font-size:12.5px; font-style:italic;
}

/* ---- sign-off -------------------------------------------------------- */
.signoff{
  display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1.6fr); gap:14px;
  margin-top:22px; padding-top:14px; border-top:2px solid var(--line);
}
.sig{border:1px solid var(--line); border-radius:10px; padding:11px 13px; background:var(--alt)}
.sig-k{
  margin:0 0 4px; font-size:9.5px; font-weight:700; letter-spacing:.1em;
  text-transform:uppercase; color:var(--faint);
}
.sig-name{
  margin:0; font-size:16px; font-weight:700; border-bottom:1px solid var(--line);
  padding-bottom:6px;
}
.sig-unsigned{color:var(--bad)}
.sig-when{margin:6px 0 0; font-size:11.5px; color:var(--muted)}
.sig-note{margin:5px 0 0; font-size:11.5px; color:var(--ink2); font-style:italic}
.conf{font-size:11px; line-height:1.5; color:var(--muted)}
.conf p{margin:0}
.conf-k{
  font-size:9.5px; font-weight:700; letter-spacing:.1em; text-transform:uppercase;
  margin-bottom:4px !important;
}
.conf-warn{margin-top:6px !important; color:var(--bad); font-weight:600}

/* ---- status ghost ----------------------------------------------------- */
.ghost{
  position:absolute; inset:0; display:grid; place-items:center; overflow:hidden;
  pointer-events:none; z-index:0; font-size:150px; font-weight:800;
  letter-spacing:.1em; color:rgba(15,23,42,.05); transform:rotate(-24deg);
}
.sheet > *:not(.ghost){position:relative; z-index:1}

.print-foot{display:none}

@media (max-width:760px){
  .tiles,.toc ol{grid-template-columns:repeat(2,minmax(0,1fr))}
  .pairs,.signoff{grid-template-columns:minmax(0,1fr)}
  .masthead h1{font-size:20px}
  .body,.masthead,.idbar{padding-left:16px; padding-right:16px}
}

/* ---- A4 --------------------------------------------------------------- */
@page{size:A4; margin:11mm 11mm 15mm}
@media print{
  html,body{background:#fff}
  body{padding:0 0 8mm; font-size:10.5pt}
  *{-webkit-print-color-adjust:exact; print-color-adjust:exact}
  .toolbar{display:none}
  .sheet{max-width:none; margin:0; border:0; border-radius:0; box-shadow:none; overflow:visible}
  .masthead{padding:12px 0 14px}
  .masthead h1{font-size:19pt}
  .idbar,.body{padding-left:0; padding-right:0}
  .body{padding-top:12px}
  /* A section title must not be the last thing on a page, and a row must
     never be sliced in half across the fold. */
  .block h2{break-after:avoid}
  tr,.note,.tile,.pair,.sig,.signoff{break-inside:avoid}
  thead{display:table-header-group}
  .tablewrap{overflow:visible}
  .ghost{position:fixed; font-size:120pt}
  /* Runs at the foot of every printed page, so a loose sheet can still be
     traced back to the report and the patient it belongs to. */
  .print-foot{
    display:block; position:fixed; bottom:-10mm; left:0; right:0; margin:0;
    font-size:7.5pt; color:#94A3B8; text-align:center;
  }
}
CSS;
    }
}
