<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Services\PatientReportAssembler;
use App\Services\PatientReportService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Doctor sign-off on customised patient reports.
 *
 * A doctor may only see and sign a report they were nominated for, and only
 * after the patient has consented — a signature must never be able to
 * pre-authorise a disclosure the patient has not yet approved.
 */
class DoctorReportSignaturesController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly PatientReportService $reports,
        private readonly PatientReportAssembler $assembler,
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

        if (! $reportRequest->consentSatisfied()) {
            return $this->error('The patient has not consented to this disclosure yet.', 422);
        }

        return $this->success([
            'report_request' => $reportRequest->toApiArray(),
            'document' => $reportRequest->status === PatientReportRequest::STATUS_ISSUED
                ? $this->reports->snapshot($reportRequest)
                : $this->assembler->assemble($reportRequest),
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
        if (! $reportRequest->consentSatisfied()) {
            return $this->error('The patient has not consented to this disclosure yet.', 422);
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
