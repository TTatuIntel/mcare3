<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Services\PatientReportRenderer;
use App\Services\PatientReportService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The patient's own view of every report drawn from their record: which
 * sections it covered, who it went to, which doctor signed it, and the report
 * itself once issued.
 *
 * It used to be an approval surface — staff asked, the patient granted or
 * refused by one-time code. That gate is gone; a doctor's signature authorises
 * the report now. What remains is the half that was always the more useful one:
 * the patient can see what was sent about them, and read it.
 *
 * Every route re-checks ownership against the authenticated user; a report
 * request id is never sufficient on its own.
 */
class PatientReportConsentsController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly PatientReportService $reports,
        private readonly PatientReportRenderer $renderer,
    ) {}

    public function index(Request $request)
    {
        $requests = PatientReportRequest::with(['requestedBy', 'doctor'])
            ->where('patient_user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();

        return $this->success([
            'report_requests' => $requests
                ->map(fn (PatientReportRequest $r) => $r->toPatientApiArray())
                ->all(),
        ]);
    }

    /**
     * The issued report itself, rendered for the patient to read, print or
     * save as PDF.
     *
     * Issuing froze the assembled report into `snapshot` and told the patient
     * it had gone out — but exposed only `has_snapshot: true`, so the person
     * the record describes was the one party who could not read what had been
     * disclosed. This serves the frozen copy, never a fresh assembly: what the
     * patient opens must be byte-for-byte what the recipient was sent, even
     * after the underlying record moves on.
     */
    public function document(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertOwned($request, $reportRequest);

        $snapshot = $this->reports->snapshot($reportRequest);
        if ($snapshot === null) {
            return $this->error('This report has not been issued yet.', 404);
        }

        // A revoked report is still shown to the patient — it was disclosed and
        // they are entitled to see what — but never without saying so.
        $watermark = $reportRequest->revoked_at !== null
            ? 'This report was revoked on '
                .$reportRequest->revoked_at->format('j M Y')
                .($reportRequest->revoke_reason ? ' — '.$reportRequest->revoke_reason : '')
                .'. It is retained here for your records only.'
            : null;

        $html = $this->renderer->toHtml($snapshot, $watermark);

        // Rendered inline rather than as an attachment: the patient asked to
        // read it, and the browser's own print dialog is the PDF route.
        return response($html, 200, [
            'Content-Type' => 'text/html; charset=UTF-8',
            'Content-Disposition' => 'inline; filename="'
                .$this->filename($reportRequest).'"',
            // A medical disclosure must not sit in a shared cache.
            'Cache-Control' => 'private, no-store, max-age=0',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    private function filename(PatientReportRequest $reportRequest): string
    {
        $slug = preg_replace('/[^A-Za-z0-9]+/', '-', (string) $reportRequest->title);
        $slug = trim((string) $slug, '-') ?: 'medical-report';

        return strtolower($slug).'-'.$reportRequest->id.'.html';
    }

    private function assertOwned(Request $request, PatientReportRequest $reportRequest): void
    {
        abort_unless(
            (int) $reportRequest->patient_user_id === (int) $request->user()->id,
            404,
            'Report request not found.',
        );
    }
}
