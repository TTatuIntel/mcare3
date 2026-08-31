<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Services\PatientReportAssembler;
use App\Services\PatientReportRenderer;
use App\Services\PatientReportService;
use App\Support\ApiResponse;
use App\Support\PatientReportSections;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Admin side of the customised patient report workflow.
 *
 * The admin ticks the sections they need; the backend — not the client —
 * decides whether that selection is confidential enough to require the
 * patient's consent and a doctor's signature. Content is only ever assembled
 * at `issue`, and only from sections the patient actually approved.
 */
class PatientReportsController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly PatientReportService $reports,
        private readonly PatientReportRenderer $renderer,
        private readonly PatientReportAssembler $assembler,
    ) {}

    /** The tick-list catalogue, so the client never hardcodes sensitivity. */
    public function sections()
    {
        return $this->success(['sections' => PatientReportSections::toApiArray()]);
    }

    public function index(Request $request)
    {
        $query = PatientReportRequest::with(['patient', 'requestedBy', 'doctor'])
            ->orderByDesc('created_at');

        if ($patientId = $request->query('patient_id')) {
            $query->where('patient_user_id', $patientId);
        }
        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }
        if ($request->boolean('open_only')) {
            $query->whereNotIn('status', [
                PatientReportRequest::STATUS_ISSUED,
                PatientReportRequest::STATUS_REVOKED,
                PatientReportRequest::STATUS_DECLINED,
                PatientReportRequest::STATUS_EXPIRED,
            ]);
        }

        // Signed and sitting on an admin's desk. Filtered here rather than in
        // the client so the badge count and the list can never disagree, and
        // so a paged list still counts what is off the first page.
        if ($request->boolean('awaiting_me')) {
            $query->whereNotNull('signed_at')
                ->whereNull('issued_at')
                ->whereNotIn('status', [
                    PatientReportRequest::STATUS_REVOKED,
                    PatientReportRequest::STATUS_DECLINED,
                    PatientReportRequest::STATUS_EXPIRED,
                ]);
        }

        return $this->success([
            'report_requests' => $query->limit(200)->get()->map->toApiArray()->all(),
        ]);
    }

    public function store(Request $request, User $patient)
    {
        abort_unless($patient->role === 'patient', 404, 'Not a patient account.');

        $data = $request->validate([
            'sections' => 'required|array|min:1',
            'sections.*' => ['string', Rule::in(PatientReportSections::keys())],
            'title' => 'required|string|max:160',
            'purpose' => 'required|string|min:4|max:280',
            'recipient' => 'nullable|string|max:160',
            'doctor_user_id' => 'nullable|exists:users,id',
        ]);

        $doctor = null;
        if (! empty($data['doctor_user_id'])) {
            $doctor = User::find($data['doctor_user_id']);
            if ($doctor && $doctor->role !== 'doctor') {
                return $this->error('Only a doctor account can be nominated to sign.', 422);
            }
        }

        $reportRequest = $this->reports->create(
            $request->user(),
            $patient,
            $data['sections'],
            $data['title'],
            $data['purpose'],
            $data['recipient'] ?? null,
            $doctor,
        );

        return $this->success(
            ['report_request' => $reportRequest->toApiArray()],
            $reportRequest->consent_required
                ? 'Consent request sent to the patient.'
                : 'Report request created.',
            201,
        );
    }

    /**
     * The request, plus the report itself whenever there is one to show.
     *
     * An issued report replays from the frozen snapshot, so a reader always
     * sees what was disclosed rather than the record as it stands today. An
     * un-issued one is assembled live — the admin is about to decide whether to
     * put this document in front of the recipient, and until now they could
     * only see the list of section *names* they had ticked at the start. That
     * made issuing an act of faith in a document nobody outside the doctor had
     * read, which is precisely the review this step exists to be.
     *
     * The gate is the patient's consent, not the doctor's signature: consent is
     * what authorises the content to be assembled at all, and it is the same
     * gate the doctor's own preview uses.
     */
    public function show(Request $request, PatientReportRequest $reportRequest)
    {
        $payload = ['report_request' => $reportRequest->toApiArray()];

        if ($reportRequest->snapshot !== null) {
            $payload['document'] = $this->reports->snapshot($reportRequest);
            $payload['document_is_draft'] = false;
        } elseif ($reportRequest->consentSatisfied() && ! $reportRequest->isTerminal()) {
            $payload['document'] = $this->assembler->assemble($reportRequest);
            $payload['document_is_draft'] = true;
        }

        return $this->success($payload);
    }

    /**
     * Send a signed report back to the doctor for a correction.
     *
     * The third exit from a signed report, alongside issuing it and discarding
     * it — and the one the other two were standing in for. An admin who spotted
     * a wrong recipient or a missing qualification had to revoke the request,
     * which discards the patient's consent with it and means going back to a
     * patient who has already agreed and asking again for the same thing.
     */
    public function sendBack(Request $request, PatientReportRequest $reportRequest)
    {
        $data = $request->validate([
            'note' => 'required|string|min:4|max:280',
        ]);

        if ($reportRequest->issued_at !== null) {
            return $this->error(
                'This report has already been issued. Revoke it instead.',
                422,
            );
        }
        if ($reportRequest->isTerminal()) {
            return $this->error('This request is closed.', 422);
        }
        if ($reportRequest->signed_at === null) {
            return $this->error('There is no signature to send back yet.', 422);
        }
        if (! $reportRequest->doctor_user_id) {
            return $this->error('No doctor is nominated on this report.', 422);
        }

        $this->reports->returnForRework($request->user(), $reportRequest, trim($data['note']));

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Sent back to the doctor for changes.',
        );
    }

    /** Reissue the OTP + approval link (patient lost it, or it expired). */
    public function resendConsent(Request $request, PatientReportRequest $reportRequest)
    {
        if ($reportRequest->isTerminal() || $reportRequest->issued_at !== null) {
            return $this->error('This request is closed.', 422);
        }
        if (! $reportRequest->consent_required) {
            return $this->error('This report does not need patient consent.', 422);
        }
        if ($reportRequest->consented_at !== null) {
            return $this->error('The patient has already consented.', 422);
        }

        $this->reports->sendConsentChallenge($request->user(), $reportRequest);

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'A new approval code and link were sent to the patient.',
        );
    }

    /**
     * Staff-assisted consent: the patient reads their code back over the
     * phone. Deliberately does not reveal whether the code was merely wrong
     * or the challenge already burned.
     */
    public function verifyConsent(Request $request, PatientReportRequest $reportRequest)
    {
        $data = $request->validate([
            'code' => 'required|string|max:12',
        ]);

        $ok = $this->reports->verifyConsentCode(
            $request->user(),
            $reportRequest,
            trim($data['code']),
        );

        if (! $ok) {
            $fresh = $reportRequest->fresh();
            $remaining = max(
                0,
                PatientReportRequest::MAX_CONSENT_ATTEMPTS - (int) $fresh->consent_attempts,
            );

            return $this->error(
                $fresh->status === PatientReportRequest::STATUS_EXPIRED
                    ? 'That approval code is no longer valid. Send the patient a new one.'
                    : "Approval code did not match. $remaining attempt(s) left.",
                422,
            );
        }

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Patient consent recorded.',
        );
    }

    public function issue(Request $request, PatientReportRequest $reportRequest)
    {
        if ($reportRequest->issued_at !== null) {
            return $this->error('This report has already been issued.', 422);
        }
        if ($reportRequest->isTerminal()) {
            return $this->error('This request is closed.', 422);
        }
        if (! $reportRequest->consentSatisfied()) {
            return $this->error('The patient has not consented to this disclosure yet.', 422);
        }
        if (! $reportRequest->signatureSatisfied()) {
            return $this->error('A doctor must sign this report before it can be issued.', 422);
        }

        $document = $this->reports->issue($request->user(), $reportRequest);

        return $this->success([
            'report_request' => $reportRequest->fresh()->toApiArray(),
            'document' => $document,
        ], 'Report issued.');
    }

    /**
     * The issued report as a file staff can save, print or send on.
     *
     * `show` already returned the snapshot as JSON, which the workspace renders
     * on screen — fine for reading, useless for the thing staff actually need
     * once a doctor has signed: a copy to hand to the recipient the report was
     * prepared for. Rendered from the frozen snapshot, so the file staff send
     * and the copy in the patient's documents are the same document.
     */
    public function document(Request $request, PatientReportRequest $reportRequest)
    {
        $snapshot = $this->reports->snapshot($reportRequest);
        $isDraft = $snapshot === null;

        if ($isDraft) {
            if (! $reportRequest->consentSatisfied() || $reportRequest->isTerminal()) {
                return $this->error(
                    'There is no report to open yet — the patient has not '
                    .'approved this disclosure.',
                    404,
                );
            }
            $snapshot = $this->assembler->assemble($reportRequest);
        }

        // Every copy that leaves the system says what it is. A draft is the
        // dangerous one: it reads exactly like the finished report, so without
        // this an admin could review one, save it, and send an unissued and
        // possibly unsigned document to the recipient believing it was final.
        $watermark = match (true) {
            $reportRequest->revoked_at !== null => 'This report was revoked on '
                .$reportRequest->revoked_at->format('j M Y')
                .($reportRequest->revoke_reason ? ' — '.$reportRequest->revoke_reason : '')
                .'. It must not be relied on or forwarded.',
            $isDraft => 'DRAFT — for internal review only. This report has not '
                .'been issued'
                .($reportRequest->signed_at === null ? ' or signed' : '')
                .' and must not be sent to anyone outside mCare.',
            default => null,
        };

        return response($this->renderer->toHtml($snapshot, $watermark), 200, [
            'Content-Type' => 'text/html; charset=UTF-8',
            'Content-Disposition' => 'inline; filename="'
                .($isDraft ? 'draft-' : '').'report-'.$reportRequest->id.'.html"',
            'Cache-Control' => 'private, no-store, max-age=0',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    public function revoke(Request $request, PatientReportRequest $reportRequest)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($reportRequest->status === PatientReportRequest::STATUS_REVOKED) {
            return $this->error('This request is already revoked.', 422);
        }

        $wasIssued = $reportRequest->issued_at !== null;

        $this->reports->revoke($request->user(), $reportRequest, $data['reason']);

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            $wasIssued
                ? 'Report revoked. The patient has been told, and their copy is '
                    .'marked as revoked.'
                : 'Report request removed. Nothing was disclosed.',
        );
    }
}
