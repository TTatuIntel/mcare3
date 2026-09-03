<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Services\PatientReportAssembler;
use App\Services\PatientReportRenderer;
use App\Services\PatientReportService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Doctor sign-off on customised patient reports.
 *
 * A doctor may only see and sign a report they were nominated for, and the
 * admin can only nominate a doctor already on the patient's care team — so
 * signing never becomes a route to a record the doctor could not otherwise
 * open.
 *
 * The signature is the single authorisation for issuing a report, which is why
 * it is given against the assembled document rather than a list of section
 * names: there is no second reader downstream who will catch what it says.
 */
class DoctorReportSignaturesController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly PatientReportService $reports,
        private readonly PatientReportAssembler $assembler,
        private readonly PatientReportRenderer $renderer,
    ) {}

    public function index(Request $request)
    {
        $requests = PatientReportRequest::with(['patient', 'requestedBy'])
            ->where('doctor_user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();

        return $this->success([
            'report_requests' => $requests->map(fn (PatientReportRequest $r) => $r->toApiArray() + [
                'awaiting_me' => $r->blockedOn() === 'doctor_signature',
            ])->all(),
        ]);
    }

    /**
     * Preview the exact document that will be issued, so the signature is
     * given against real content rather than a list of section names.
     */
    public function preview(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertNominated($request, $reportRequest);

        return $this->success([
            'report_request' => $reportRequest->toApiArray(),
            'document' => $reportRequest->status === PatientReportRequest::STATUS_ISSUED
                ? $this->reports->snapshot($reportRequest)
                : $this->assembler->assemble($reportRequest),
        ]);
    }

    /**
     * The same report as a real page the doctor can open, scroll and print.
     *
     * `preview` renders it inside a sheet, which is fine for a glance and poor
     * for the thing a signature actually requires — reading a long document
     * properly, at full width, next to the chart. A signature given against a
     * cramped in-app summary is a signature given against a summary.
     *
     * Watermarked as a draft: before signing this is not a report, and a copy
     * saved out of the browser must not be able to pass for one.
     */
    public function document(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertNominated($request, $reportRequest);

        $snapshot = $this->reports->snapshot($reportRequest);
        $isDraft = $snapshot === null;

        if ($isDraft) {
            if ($reportRequest->isTerminal()) {
                return $this->error('This request is closed.', 404);
            }
            $snapshot = $this->assembler->assemble($reportRequest);
        }

        $watermark = $isDraft
            ? 'DRAFT — for clinical review before signing. This report has not '
                .'been issued'
                .($reportRequest->signed_at === null ? ' or signed' : '')
                .' and must not be given to anyone outside mCare.'
            : null;

        return response($this->renderer->toHtml($snapshot, $watermark, [
            'status' => $isDraft ? 'draft' : 'issued',
            'reference' => 'RPT-'.$reportRequest->id,
        ]), 200, [
            'Content-Type' => 'text/html; charset=UTF-8',
            'Content-Disposition' => 'inline; filename="'
                .($isDraft ? 'draft-' : '').'report-'.$reportRequest->id.'.html"',
            'Cache-Control' => 'private, no-store, max-age=0',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    public function sign(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertNominated($request, $reportRequest);

        $data = $request->validate([
            'signature_name' => 'required|string|min:2|max:160',
            'note' => 'nullable|string|max:280',
        ]);

        if ($reportRequest->isTerminal() || $reportRequest->issued_at !== null) {
            return $this->error('This request is closed.', 422);
        }
        if ($reportRequest->signed_at !== null) {
            return $this->error('This report is already signed.', 422);
        }

        $this->reports->sign(
            $request->user(),
            $reportRequest,
            $data['signature_name'],
            $data['note'] ?? null,
        );

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Report signed.',
        );
    }

    public function decline(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertNominated($request, $reportRequest);

        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($reportRequest->isTerminal() || $reportRequest->issued_at !== null) {
            return $this->error('This request is closed.', 422);
        }

        $this->reports->declineSignature($request->user(), $reportRequest, $data['reason']);

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Signature declined — the report cannot be issued.',
        );
    }

    private function assertNominated(Request $request, PatientReportRequest $reportRequest): void
    {
        abort_unless(
            (int) $reportRequest->doctor_user_id === (int) $request->user()->id,
            404,
            'Report request not found.',
        );
    }
}
