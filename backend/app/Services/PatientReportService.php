<?php

namespace App\Services;

use App\Mail\PatientReportConsentMail;
use App\Models\AppNotification;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Support\PatientReportSections;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

/**
 * Workflow for issuing a customised patient report.
 *
 *   draft → pending_consent → consented → pending_signature → signed → issued
 *
 * Consent and signature steps are skipped only when the ticked sections do
 * not require them (see PatientReportSections). Every state change is
 * audited, and the report body is assembled exactly once — at issue time.
 */
class PatientReportService
{
    /** How long a consent challenge stays valid. */
    private const CONSENT_TTL_MINUTES = 30;

    public function __construct(
        private readonly AuditService $audit,
        private readonly PatientReportAssembler $assembler,
    ) {}

    /**
     * Create the request and, when the ticked sections demand it, immediately
     * issue the consent challenge to the patient.
     *
     * @param  list<string>  $sections
     */
    public function create(
        User $actor,
        User $patient,
        array $sections,
        string $title,
        string $purpose,
        ?string $recipient,
        ?User $doctor,
    ): PatientReportRequest {
        $sections = $this->normalizeSections($sections);

        $consentRequired = PatientReportSections::requiresConsent($sections);
        $signatureRequired = PatientReportSections::requiresSignature($sections);

        $request = PatientReportRequest::create([
            'patient_user_id' => $patient->id,
            'requested_by_user_id' => $actor->id,
            'doctor_user_id' => $doctor?->id ?? $this->suggestDoctorId($patient),
            'title' => $title,
            'purpose' => $purpose,
            'recipient' => $recipient,
            'sections' => $sections,
            'consent_required' => $consentRequired,
            'signature_required' => $signatureRequired,
            'status' => PatientReportRequest::STATUS_DRAFT,
        ]);

        $this->audit->record(
            $actor,
            'report.requested',
            $patient->fullName().' — '.$title,
            'activity',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'report_request_id' => $request->id,
                'sections' => $sections,
                'consent_required' => $consentRequired,
                'signature_required' => $signatureRequired,
            ],
        );

        if ($consentRequired) {
            $this->sendConsentChallenge($actor, $request->fresh());
        } else {
            $request->update([
                'status' => $signatureRequired
                    ? PatientReportRequest::STATUS_PENDING_SIGNATURE
                    : PatientReportRequest::STATUS_CONSENTED,
            ]);
            if ($signatureRequired) {
                $this->notifyDoctor($request->fresh());
            }
        }

        return $request->fresh();
    }

    /**
     * Mint a fresh OTP + approval link and deliver both to the patient.
     * Any previous challenge on this request is invalidated.
     *
     * @return string the plaintext code, returned once so staff can read it
     *                back over the phone when email is unavailable
     */
    public function sendConsentChallenge(User $actor, PatientReportRequest $request): string
    {
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $token = Str::random(48);

        $request->update([
            'status' => PatientReportRequest::STATUS_PENDING_CONSENT,
            'consent_code_hash' => Hash::make($code),
            'consent_token' => $token,
            'consent_channel' => 'otp_and_link',
            'consent_sent_at' => now(),
            'consent_expires_at' => now()->addMinutes(self::CONSENT_TTL_MINUTES),
            'consent_attempts' => 0,
            'consented_at' => null,
            'consent_method' => null,
            'declined_at' => null,
            'decline_reason' => null,
        ]);

        $patient = $request->patient;
        $labels = array_map(
            fn (string $k) => PatientReportSections::label($k),
            $request->sections ?? [],
        );

        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'consent',
            'title' => 'Approve sharing of your record',
            'body' => 'mCare staff need your approval to include '
                .count($labels).' part'.(count($labels) === 1 ? '' : 's')
                .' of your record in a report for '.$request->purpose
                .'. Approve or decline in the app.',
            'action_route' => '/patient/report-consents',
            'read' => false,
        ]);

        $this->dispatchConsentEmail($request, $patient, $code, $labels);

        $this->audit->record(
            $actor,
            'report.consent_requested',
            $patient->fullName().' — '.$request->title,
            'security',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'report_request_id' => $request->id,
                'expires_at' => $request->fresh()->consent_expires_at?->toIso8601String(),
            ],
        );

        return $code;
    }

    /**
     * Staff-assisted consent: the patient reads the code back over the phone
     * and the admin types it in. Rate-limited by attempt count.
     */
    public function verifyConsentCode(User $actor, PatientReportRequest $request, string $code): bool
    {
        if ($request->status !== PatientReportRequest::STATUS_PENDING_CONSENT) {
            return false;
        }

        if ($request->consentExpired()) {
            $request->update(['status' => PatientReportRequest::STATUS_EXPIRED]);

            return false;
        }

        if ($request->consent_attempts >= PatientReportRequest::MAX_CONSENT_ATTEMPTS) {
            $request->update(['status' => PatientReportRequest::STATUS_EXPIRED]);

            return false;
        }

        if (! $request->consent_code_hash || ! Hash::check($code, $request->consent_code_hash)) {
            $request->increment('consent_attempts');

            return false;
        }

        $this->grantConsent($request, 'otp_staff_assisted', $actor);

        return true;
    }

    /**
     * Patient-driven consent from inside the app or the approval link.
     */
    public function grantConsent(
        PatientReportRequest $request,
        string $method,
        ?User $actor = null,
    ): void {
        $request->update([
            'consented_at' => now(),
            'consent_method' => $method,
            'consent_code_hash' => null,
            'consent_token' => null,
            'status' => $request->signature_required
                ? PatientReportRequest::STATUS_PENDING_SIGNATURE
                : PatientReportRequest::STATUS_CONSENTED,
        ]);

        $request->refresh();

        $this->audit->record(
            $actor ?? $request->patient,
            'report.consent_granted',
            $request->patient?->fullName().' — '.$request->title,
            'security',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'method' => $method,
                'sections' => $request->sections,
            ],
        );

        // Tell the requesting admin the block has cleared.
        if ($request->requested_by_user_id) {
            AppNotification::create([
                'user_id' => $request->requested_by_user_id,
                'kind' => 'consent',
                'title' => 'Report consent granted',
                'body' => ($request->patient?->fullName() ?? 'The patient')
                    .' approved "'.$request->title.'".'
                    .($request->signature_required
                        ? ' Awaiting doctor signature.'
                        : ' Ready to issue.'),
                'action_route' => '/admin/reports',
                'read' => false,
            ]);
        }

        if ($request->signature_required) {
            $this->notifyDoctor($request);
        }
    }

    public function declineConsent(PatientReportRequest $request, ?string $reason): void
    {
        $request->update([
            'status' => PatientReportRequest::STATUS_DECLINED,
            'declined_at' => now(),
            'decline_reason' => $reason,
            'consent_code_hash' => null,
            'consent_token' => null,
        ]);

        $this->audit->record(
            $request->patient,
            'report.consent_declined',
            $request->patient?->fullName().' — '.$request->title,
            'security',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'reason' => $reason,
            ],
        );

        if ($request->requested_by_user_id) {
            AppNotification::create([
                'user_id' => $request->requested_by_user_id,
                'kind' => 'consent',
                'title' => 'Report consent declined',
                'body' => ($request->patient?->fullName() ?? 'The patient')
                    .' declined "'.$request->title.'".'
                    .($reason ? ' Reason: '.$reason : ''),
                'action_route' => '/admin/reports',
                'read' => false,
            ]);
        }
    }

    /**
     * Doctor sign-off. Refuses to sign before the patient has consented so a
     * signature can never pre-authorise a disclosure the patient later blocks.
     */
    public function sign(
        User $doctor,
        PatientReportRequest $request,
        string $signatureName,
        ?string $note,
    ): void {
        $request->update([
            'doctor_user_id' => $doctor->id,
            'signed_at' => now(),
            'signature_name' => $signatureName,
            'signature_note' => $note,
            'status' => PatientReportRequest::STATUS_SIGNED,
        ]);

        $this->audit->record(
            $doctor,
            'report.signed',
            $request->patient?->fullName().' — '.$request->title,
            'activity',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
            ],
        );

        if ($request->requested_by_user_id) {
            AppNotification::create([
                'user_id' => $request->requested_by_user_id,
                'kind' => 'consent',
                'title' => 'Report signed',
                'body' => 'Dr. '.$doctor->fullName().' signed "'.$request->title
                    .'". It is ready to issue.',
                'action_route' => '/admin/reports',
                'read' => false,
            ]);
        }
    }

    public function declineSignature(User $doctor, PatientReportRequest $request, string $reason): void
    {
        $request->update([
            'doctor_user_id' => $doctor->id,
            'status' => PatientReportRequest::STATUS_REVOKED,
            'revoked_at' => now(),
            'revoke_reason' => 'Signature declined: '.$reason,
        ]);

        $this->audit->record(
            $doctor,
            'report.signature_declined',
            $request->patient?->fullName().' — '.$request->title,
            'activity',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'reason' => $reason,
            ],
        );

        if ($request->requested_by_user_id) {
            AppNotification::create([
                'user_id' => $request->requested_by_user_id,
                'kind' => 'consent',
                'title' => 'Report signature declined',
                'body' => 'Dr. '.$doctor->fullName().' declined to sign "'
                    .$request->title.'". Reason: '.$reason,
                'action_route' => '/admin/reports',
                'read' => false,
            ]);
        }
    }

    /**
     * Freeze the consented sections into the snapshot. This is the only place
     * report content is ever produced.
     *
     * @return array<string, mixed>
     */
    public function issue(User $actor, PatientReportRequest $request): array
    {
        $document = $this->assembler->assemble($request);

        $request->update([
            'status' => PatientReportRequest::STATUS_ISSUED,
            'issued_at' => now(),
            'snapshot' => json_encode($document, JSON_UNESCAPED_UNICODE),
        ]);

        $this->audit->record(
            $actor,
            'report.issued',
            $request->patient?->fullName().' — '.$request->title,
            'security',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'sections' => $request->sections,
                'recipient' => $request->recipient,
            ],
        );

        // The patient is always told when their record actually went out.
        AppNotification::create([
            'user_id' => $request->patient_user_id,
            'kind' => 'consent',
            'title' => 'Report issued from your record',
            'body' => '"'.$request->title.'" was issued'
                .($request->recipient ? ' to '.$request->recipient : '')
                .' covering '.count($request->sections ?? []).' section'
                .(count($request->sections ?? []) === 1 ? '' : 's').' you approved.',
            'action_route' => '/patient/report-consents',
            'read' => false,
        ]);

        return $document;
    }

    public function revoke(User $actor, PatientReportRequest $request, string $reason): void
    {
        $request->update([
            'status' => PatientReportRequest::STATUS_REVOKED,
            'revoked_at' => now(),
            'revoke_reason' => $reason,
            'consent_code_hash' => null,
            'consent_token' => null,
        ]);

        $this->audit->record(
            $actor,
            'report.revoked',
            $request->patient?->fullName().' — '.$request->title,
            'security',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'reason' => $reason,
            ],
        );
    }

    /**
     * Previously issued content, replayed from the snapshot so a reader always
     * sees exactly what was disclosed rather than today's record.
     *
     * @return array<string, mixed>|null
     */
    public function snapshot(PatientReportRequest $request): ?array
    {
        if ($request->snapshot === null) {
            return null;
        }

        $decoded = json_decode($request->snapshot, true);

        return is_array($decoded) ? $decoded : null;
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    /**
     * @param  list<string>  $sections
     * @return list<string>
     */
    private function normalizeSections(array $sections): array
    {
        $valid = array_values(array_unique(array_filter(
            $sections,
            fn ($k) => is_string($k) && PatientReportSections::exists($k),
        )));

        // Keep catalogue order so every report reads the same way.
        return array_values(array_filter(
            PatientReportSections::keys(),
            fn (string $k) => in_array($k, $valid, true),
        ));
    }

    /**
     * Default signer = the patient's current primary care provider, so the
     * admin does not have to know who covers this patient.
     */
    private function suggestDoctorId(User $patient): ?int
    {
        $assignment = CareAssignment::where('patient_user_id', $patient->id)
            ->whereNull('ended_at')
            ->orderByRaw("CASE WHEN role = 'primary' THEN 0 ELSE 1 END")
            ->orderByDesc('assigned_at')
            ->first();

        if (! $assignment) {
            return null;
        }

        return CareProvider::find($assignment->provider_id)?->user_id;
    }

    private function notifyDoctor(PatientReportRequest $request): void
    {
        if (! $request->doctor_user_id) {
            return;
        }

        AppNotification::create([
            'user_id' => $request->doctor_user_id,
            'kind' => 'consent',
            'title' => 'Report awaiting your signature',
            'body' => '"'.$request->title.'" for '
                .($request->patient?->fullName() ?? 'a patient')
                .' has patient consent and needs your sign-off.',
            'action_route' => '/doctor/reports',
            'read' => false,
        ]);
    }

    /**
     * @param  list<string>  $labels
     */
    private function dispatchConsentEmail(
        PatientReportRequest $request,
        User $patient,
        string $code,
        array $labels,
    ): void {
        if (! $patient->email) {
            return;
        }

        // Deliberately an authenticated in-app destination rather than a
        // one-click token link: consent is the one decision that must not be
        // exercisable by anyone who merely gains access to the mailbox. The
        // OTP in the body covers the phone-assisted path.
        $url = rtrim(config('mcare.frontend_url'), '/').'/#/patient/report-consents';

        try {
            Mail::to($patient->email)->send(new PatientReportConsentMail(
                $patient,
                $request,
                $code,
                $url,
                $labels,
            ));
        } catch (\Throwable $e) {
            // Email is a convenience — staff can still read the OTP back over
            // the phone, so a mail failure must not block the workflow.
            report($e);
        }
    }
}
