<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\PatientReportRequest;
use App\Models\User;
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

    public function __construct(private readonly PatientReportService $reports) {}

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

    public function show(Request $request, PatientReportRequest $reportRequest)
    {
        $payload = ['report_request' => $reportRequest->toApiArray()];

        // Issued reports replay from the frozen snapshot, so a reader always
        // sees what was disclosed rather than the record as it stands today.
        if ($reportRequest->status === PatientReportRequest::STATUS_ISSUED) {
            $payload['document'] = $this->reports->snapshot($reportRequest);
        }

        return $this->success($payload);
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

    public function revoke(Request $request, PatientReportRequest $reportRequest)
    {
        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($reportRequest->status === PatientReportRequest::STATUS_REVOKED) {
            return $this->error('This request is already revoked.', 422);
        }

        $this->reports->revoke($request->user(), $reportRequest, $data['reason']);

        return $this->success(
            ['report_request' => $reportRequest->fresh()->toApiArray()],
            'Report request revoked.',
        );
    }
}
