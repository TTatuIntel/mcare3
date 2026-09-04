<?php

namespace App\Support;

use App\Models\AppNotification;
use App\Models\ClinicalReport;
use App\Models\MedicalDocument;

/**
 * Publishing a clinical report, and actually delivering it.
 *
 * Publishing used to mean two things: a boolean on a row, and a notification
 * saying "New clinical report" whose action route was `/patient/documents`.
 * Nothing ever put a document there. The patient was told a report existed,
 * sent to the one screen where their records live, and found nothing — which
 * reads as an app that lies rather than a report that is late.
 *
 * There were two ways to publish one (the doctor's reports screen and a note
 * written from the chart) and they announced it differently — the chart note
 * did not announce it at all. Both go through here now, so "published" means
 * the same thing however it was written: a file in the patient's documents and
 * one notification pointing at it.
 */
final class ClinicalReportPublisher
{
    /**
     * Files [$report] into the patient's documents and tells them.
     *
     * Idempotent: republishing, or editing an already-published report, updates
     * the copy the patient holds rather than filing a second one, and does not
     * announce it twice.
     *
     * [$announce] is false only for the retrospective backfill of reports that
     * were published before any of this existed.
     */
    public static function publish(
        ClinicalReport $report,
        string $authorLabel,
        bool $announce = true,
    ): ?MedicalDocument {
        if (! $report->published) {
            return null;
        }

        $existing = MedicalDocument::where('clinical_report_id', $report->id)->first();

        if ($existing !== null) {
            // Already delivered. Refresh the content so a corrected report does
            // not leave the patient reading a superseded one, and stay quiet —
            // they were told the first time.
            return ReportDocumentFiler::refile(
                $existing,
                $report->title,
                self::render($report, $authorLabel),
            );
        }

        $document = ReportDocumentFiler::file(
            ownerUserId: (int) $report->patient_user_id,
            title: $report->title,
            html: self::render($report, $authorLabel),
            category: 'report',
            uploadedBy: $authorLabel,
            description: 'Clinical report published by '.$authorLabel
                .' on '.now()->format('j M Y').'.',
            linkColumn: 'clinical_report_id',
            linkId: (int) $report->id,
        );

        // Reports published before delivery existed are filed retrospectively;
        // their patients were already told at the time, and telling them again
        // would claim something new had happened.
        if ($announce) {
            self::notifyPatient($report, $document);
        }

        return $document;
    }

    /**
     * The patient is told once, when the report first reaches them.
     *
     * Carries the report id so the app can open the right document straight
     * from the notification rather than dropping the reader at the top of a
     * list to go hunting.
     */
    private static function notifyPatient(
        ClinicalReport $report,
        ?MedicalDocument $document,
    ): void {
        try {
            AppNotification::create([
                'user_id' => $report->patient_user_id,
                'kind' => 'report',
                'title' => 'New clinical report',
                'body' => $report->title,
                'action_route' => '/patient/documents',
                'action_arguments' => array_filter([
                    'report_id' => (string) $report->id,
                    // The document is what the patient actually opens. Without
                    // it the alert could only reach the list, not the report.
                    'document_id' => $document?->id === null
                        ? null
                        : (string) $document->id,
                ]),
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            // A notification is not worth failing a publication that has
            // already happened and already filed the document.
            report($e);
        }
    }

    /**
     * The report as the patient reads it.
     *
     * Plain and printable on purpose: this is a document someone may hand to a
     * receptionist at another practice, so it names the patient, the author and
     * the date without needing the app to explain it.
     */
    private static function render(ClinicalReport $report, string $authorLabel): string
    {
        $title = self::e($report->title);
        $author = self::e($authorLabel);
        $patient = self::e($report->patient?->fullName() ?? 'Patient');
        $published = self::e(
            $report->published_at?->format('j M Y, H:i')
            ?? $report->created_at?->format('j M Y, H:i')
            ?? ''
        );

        // The body is free text a clinician typed. Escaped, then only the line
        // breaks they intended are turned back into markup — anything else
        // would let a pasted fragment style or script the document.
        $body = nl2br(self::e((string) ($report->body ?? '')), false);
        if (trim(strip_tags($body)) === '') {
            $body = '<p class="empty">This report has no written content.</p>';
        } else {
            $body = '<p>'.$body.'</p>';
        }

        $css = self::styles();

        return <<<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{$title}</title>
<style>{$css}</style></head><body>
<header>
  <h1>{$title}</h1>
  <p class="meta">Patient <b>{$patient}</b><br>
  Written by <b>{$author}</b> · Published {$published}</p>
</header>
<section>{$body}</section>
<footer>Issued through mCare by the clinician named above. Read alongside the
full clinical record.</footer>
</body></html>
HTML;
    }

    private static function styles(): string
    {
        return <<<'CSS'
:root{color-scheme:light}
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;
  padding:2rem;color:#16162b;background:#fff;line-height:1.6}
header{border-bottom:2px solid #5146e5;padding-bottom:1rem;margin-bottom:1.5rem}
h1{font-size:1.35rem;margin:0 0 .35rem}
.meta{color:#555;font-size:.85rem;margin:0}
.meta b{color:#16162b}
section{margin:0 0 1rem;padding:1rem;border:1px solid #e5e7eb;border-radius:10px}
.empty{color:#6b7280;font-size:.9rem;margin:0}
footer{margin-top:2rem;padding-top:1rem;border-top:1px solid #e5e7eb;
  color:#6b7280;font-size:.78rem}
@media print{body{padding:0}section{break-inside:avoid}}
CSS;
    }

    private static function e(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}
