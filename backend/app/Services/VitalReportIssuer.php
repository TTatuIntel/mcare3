<?php

namespace App\Services;

use App\Models\MedicalDocument;
use App\Models\User;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use App\Support\DocumentDelivery;
use App\Support\ReportDocumentFiler;
use App\Support\VitalLabels;
use Illuminate\Support\Collection;

/**
 * Turns a fulfilled vital report request into a document the patient owns.
 *
 * Before this, "fulfilled" meant a status flag and a free-text note: the
 * patient was told their report was ready and then had nothing to open. The
 * only rendering that existed was built in the browser from whatever readings
 * the app happened to have cached, so two people opening the same report could
 * see different numbers, and printing it a month later re-derived it from a
 * record that had moved on.
 *
 * The report is therefore rendered once, here, from the readings inside the
 * requested window, and stored as a file. What the patient opens next year is
 * what the clinician signed off today.
 */
class VitalReportIssuer
{
    /**
     * Renders and files the report for [$request], returning the document.
     *
     * Idempotent: a request that already carries a document keeps it rather
     * than filing a second copy, so a retry after a partial failure cannot
     * leave the patient with duplicates.
     */
    public function issue(
        VitalReportRequest $request,
        User $author,
        string $authorLabel,
        ?string $note = null,
    ): ?MedicalDocument {
        if ($request->document_id && $request->document) {
            return $request->document;
        }

        // A request whose document row was deleted, or whose id was written
        // while the row never landed, must not silently render a second copy
        // under a stale link. Re-reading from the database rather than trusting
        // the loaded relation is what makes a retry safe.
        if ($request->document_id) {
            $existing = MedicalDocument::find($request->document_id);
            if ($existing) {
                return $existing;
            }
        }

        $patient = $request->user;
        $title = $this->title($request);

        $document = ReportDocumentFiler::file(
            ownerUserId: (int) $request->user_id,
            title: $title,
            html: $this->render($request, $patient, $authorLabel, $note),
            category: 'vitalReport',
            uploadedBy: $authorLabel,
            description: 'Vital report you requested on '
                .$request->created_at?->format('j M Y')
                .', prepared by '.$authorLabel.'.',
        );

        // The clinician's work is already recorded on the request. Losing the
        // rendered copy is bad; failing the whole fulfilment and leaving them
        // unsure whether to write it again is worse — the filer never throws.
        if ($document !== null) {
            DocumentDelivery::notifyOwner($document, $authorLabel);
        }

        return $document;
    }

    private function title(VitalReportRequest $request): string
    {
        $from = $request->range_from?->format('j M Y') ?? '';
        $to = $request->range_to?->format('j M Y') ?? '';

        return trim("Vital report — $from to $to");
    }

    /** @return Collection<int, VitalReading> */
    private function readings(VitalReportRequest $request, string $vitalKey): Collection
    {
        return VitalReading::where('user_id', $request->user_id)
            ->where('vital_key', $vitalKey)
            ->whereBetween('recorded_at', [
                $request->range_from?->copy()->startOfDay() ?? now()->subYear(),
                $request->range_to?->copy()->endOfDay() ?? now(),
            ])
            ->orderBy('recorded_at')
            ->get();
    }

    private function render(
        VitalReportRequest $request,
        ?User $patient,
        string $authorLabel,
        ?string $note,
    ): string {
        $patientName = $this->e($patient?->fullName() ?? 'Patient');
        $period = $this->e(
            ($request->range_from?->format('j M Y') ?? '?')
            .' – '.($request->range_to?->format('j M Y') ?? '?')
        );
        $requested = $this->e($request->created_at?->format('j M Y, H:i') ?? '');
        $issued = $this->e(now()->format('j M Y, H:i'));
        $author = $this->e($authorLabel);
        $patientNote = $request->note
            ? '<section><h2>Why it was requested</h2><p>'.$this->e($request->note).'</p></section>'
            : '';
        $clinicalNote = $note
            ? '<section><h2>Clinical note</h2><p>'.$this->e($note).'</p></section>'
            : '';

        $sections = '';
        foreach ($request->vitals ?? [] as $vitalKey) {
            $sections .= $this->vitalSection((string) $vitalKey, $request);
        }
        if ($sections === '') {
            $sections = '<section><p class="empty">No vitals were selected for this report.</p></section>';
        }

        $signature = $this->signatureBlock($request, $authorLabel);
        $css = $this->styles();

        return <<<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vital report — {$patientName}</title>
<style>{$css}</style></head><body>
<header>
  <h1>Vital report — {$patientName}</h1>
  <p class="meta">Period <b>{$period}</b> · Requested {$requested} · Issued {$issued}<br>
  Prepared by <b>{$author}</b></p>
</header>
{$patientNote}
{$clinicalNote}
{$sections}
{$signature}
<footer>Generated by mCare from the readings recorded in this period. Figures
summarise self-reported and clinic-recorded values and should be read alongside
the full record.</footer>
</body></html>
HTML;
    }

    /**
     * Who attested to this report.
     *
     * The clinician who fulfils the request signs it — that act is recorded on
     * the request, and this renders the same fact into the document, so a copy
     * printed and filed on paper still carries the attestation. A report that
     * somehow reaches rendering unsigned says so rather than quietly implying
     * one; an unsigned clinical document that looks signed is the worse
     * failure by a distance.
     */
    private function signatureBlock(VitalReportRequest $request, string $authorLabel): string
    {
        $name = $this->e($request->signed_by ?? $authorLabel);
        $role = match ($request->signed_by_role) {
            'doctor' => 'Attending clinician',
            'admin' => 'Care administrator',
            'mcare_assistant' => 'Care team',
            default => 'Care team',
        };
        $signedAt = $request->signed_at;

        if ($signedAt === null) {
            return '<section class="sig"><h2>Signature</h2>'
                .'<p class="empty">This copy was rendered before it was signed off.</p>'
                .'</section>';
        }

        return '<section class="sig"><h2>Signed off</h2>'
            .'<p class="attest">I have reviewed the readings summarised above for '
            .'the period stated and issue this report as an accurate record of '
            .'what was recorded.</p>'
            .'<div class="sig-line"><span class="sig-name">'.$name.'</span>'
            .'<span class="sig-role">'.$this->e($role).'</span></div>'
            .'<p class="meta">Signed '.$this->e($signedAt->format('j M Y, H:i')).'</p>'
            .'</section>';
    }

    private function styles(): string
    {
        return <<<'CSS'
:root{color-scheme:light}
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;
  padding:2rem;color:#16162b;background:#fff;line-height:1.5}
header{border-bottom:2px solid #5146e5;padding-bottom:1rem;margin-bottom:1.5rem}
h1{font-size:1.35rem;margin:0 0 .35rem}
h2{font-size:.95rem;margin:0 0 .5rem;color:#5146e5}
.meta{color:#555;font-size:.85rem}
.meta b{color:#16162b}
section{margin:0 0 1rem;padding:1rem;border:1px solid #e5e7eb;border-radius:10px}
table{width:100%;border-collapse:collapse;margin-top:.6rem;font-size:.85rem}
th,td{text-align:left;padding:.45rem;border-bottom:1px solid #eef0f4}
th{color:#555;font-weight:600;font-size:.78rem;text-transform:uppercase;
  letter-spacing:.03em}
.empty{color:#6b7280;font-size:.9rem;margin:0}
.trend{font-weight:600;color:#5146e5;font-size:.85rem}
.chart{width:100%;height:92px;margin-top:.6rem}
footer{margin-top:2rem;padding-top:1rem;border-top:1px solid #e5e7eb;
  color:#6b7280;font-size:.78rem}
.sig{border-color:#5146e5;background:#f8f7ff}
.attest{font-size:.85rem;color:#3f3f5a;margin:0 0 1rem}
.sig-line{border-top:1px solid #5146e5;padding-top:.5rem;margin-top:1.75rem;
  display:flex;flex-direction:column;gap:.15rem;max-width:20rem}
.sig-name{font-weight:700;font-size:.95rem}
.sig-role{color:#555;font-size:.78rem;text-transform:uppercase;
  letter-spacing:.04em}
@media print{body{padding:0}section{break-inside:avoid}}
CSS;
    }

    private function vitalSection(string $vitalKey, VitalReportRequest $request): string
    {
        $label = $this->e(VitalLabels::label($vitalKey));
        $unit = VitalLabels::unit($vitalKey);
        $readings = $this->readings($request, $vitalKey);

        if ($readings->isEmpty()) {
            return "<section><h2>$label</h2>"
                .'<p class="empty">No readings recorded in this period.</p></section>';
        }

        $values = $readings->map(fn ($r) => (float) $r->value);
        $count = $values->count();
        $normal = $readings->filter(fn ($r) => $r->risk === 'normal')->count();
        $inRange = (int) round($normal / $count * 100);
        $trend = $this->trendLabel($values->values()->all());

        $fmt = function (?float $v) use ($vitalKey, $unit): string {
            if ($v === null) {
                return '—';
            }
            $decimals = in_array($vitalKey, ['temperature', 'weight'], true) ? 1 : 0;
            $n = number_format($v, $decimals, '.', '');

            return $this->e($unit !== '' ? "$n $unit" : $n);
        };

        $latest = $readings->last();
        $latestLine = '<p class="meta">Latest: <b>'.$this->e($latest->displayValue())
            .'</b> on '.$this->e($latest->recorded_at?->format('j M Y, H:i') ?? '').'</p>';

        return "<section><h2>$label</h2>"
            .'<div class="trend">'.$this->e($trend).' trend</div>'
            .$this->sparkline($values->values()->all())
            .'<table><thead><tr><th>Readings</th><th>Average</th><th>Lowest</th>'
            .'<th>Highest</th><th>In range</th></tr></thead><tbody><tr>'
            ."<td>$count</td><td>{$fmt($values->avg())}</td><td>{$fmt($values->min())}</td>"
            ."<td>{$fmt($values->max())}</td><td>$inRange%</td>"
            .'</tr></tbody></table>'
            .$latestLine
            .'</section>';
    }

    /**
     * First half of the window against the second. Crude on purpose: a report
     * that claimed a trend from a linear fit over eight readings would be
     * asserting more than the data supports.
     *
     * @param  list<float>  $values
     */
    private function trendLabel(array $values): string
    {
        if (count($values) < 4) {
            return 'Steady';
        }

        $half = intdiv(count($values), 2);
        $first = array_slice($values, 0, $half);
        $second = array_slice($values, $half);
        $a = array_sum($first) / max(count($first), 1);
        $b = array_sum($second) / max(count($second), 1);

        if ($a == 0.0) {
            return 'Steady';
        }
        $change = ($b - $a) / abs($a) * 100;

        return match (true) {
            $change > 5 => 'Rising',
            $change < -5 => 'Falling',
            default => 'Steady',
        };
    }

    /** @param  list<float>  $values */
    private function sparkline(array $values): string
    {
        if (count($values) < 2) {
            return '';
        }

        $width = 520.0;
        $height = 82.0;
        $low = min($values);
        $high = max($values);
        $span = $high == $low ? 1.0 : $high - $low;

        $points = [];
        foreach (array_values($values) as $i => $v) {
            $x = $i / (count($values) - 1) * $width;
            $y = $height - (($v - $low) / $span * ($height - 12)) - 6;
            $points[] = round($x, 1).','.round($y, 1);
        }

        return '<svg class="chart" viewBox="0 0 520 82" preserveAspectRatio="none" '
            .'role="img" aria-label="Trend chart">'
            .'<polyline fill="none" stroke="#5146e5" stroke-width="3" '
            .'stroke-linecap="round" stroke-linejoin="round" points="'
            .implode(' ', $points).'"/></svg>';
    }

    private function e(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}
