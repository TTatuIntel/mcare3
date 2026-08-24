<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Services\PatientReportService;
use App\Support\ApiResponse;
use App\Support\PatientReportSections;
use Illuminate\Http\Request;

/**
 * Patient-facing consent surface: see exactly which parts of the record staff
 * want to disclose, to whom, and why — then approve or decline.
 *
 * Every route re-checks ownership against the authenticated user; a report
 * request id is never sufficient on its own.
 */
class PatientReportConsentsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly PatientReportService $reports) {}

    public function index(Request $request)
    {
        $requests = PatientReportRequest::with(['requestedBy', 'doctor'])
            ->where('patient_user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();

        return $this->success([
            'report_requests' => $requests->map(fn (PatientReportRequest $r) => $r->toApiArray() + [
                // The patient sees plain descriptions, not just section keys.
                'section_details' => array_map(fn (string $k) => [
                    'key' => $k,
                    'label' => PatientReportSections::label($k),
                    'description' => PatientReportSections::CATALOG[$k]['description'] ?? '',
                ], $r->sections ?? []),
                'awaiting_me' => $r->status === PatientReportRequest::STATUS_PENDING_CONSENT
                    && ! $r->consentExpired(),
            ])->all(),
        ]);
    }

    public function approve(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertOwned($request, $reportRequest);

        if ($reportRequest->consented_at !== null) {
            return $this->success(
                ['report_request' => $reportRequest->toApiArray()],
                'You have already approved this request.',
            );
        }
        if ($reportRequest->isTerminal()) {
            return $this->error('This request is no longer open.', 422);
        }
        if ($reportRequest->consentExpired()) {
            $reportRequest->update(['status' => PatientReportRequest::STATUS_EXPIRED]);

            return $this->error(
                'This approval request has expired. Ask mCare to send a new one.',
                422,
            );
        }

        $this->reports->grantConsent($reportRequest, 'in_app', $request->user());

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Thank you — your approval has been recorded.',
        );
    }

    public function decline(Request $request, PatientReportRequest $reportRequest)
    {
        $this->assertOwned($request, $reportRequest);

        $data = $request->validate([
            'reason' => 'nullable|string|max:280',
        ]);

        if ($reportRequest->isTerminal()) {
            return $this->error('This request is no longer open.', 422);
        }

        $this->reports->declineConsent($reportRequest, $data['reason'] ?? null);

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Declined — nothing from your record will be shared.',
        );
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
