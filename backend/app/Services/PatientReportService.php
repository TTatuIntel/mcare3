<?php

namespace App\Services;

use App\Mail\ReportIssuedMail;
use App\Models\AppNotification;
use App\Models\MedicalDocument;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Support\DocumentDelivery;
use App\Support\MailDispatcher;
use App\Support\MedicalDocumentFiles;
use App\Support\PatientReportSections;

/**
 * Workflow for issuing a customised patient report.
 *
 *   draft → pending_signature → signed → issued
 *                             ↘ under_review   (admin parked it)
 *                             ↘ returned       (back to the doctor)
 *                             ↘ rejected       (deleted, never disclosed)
 *
 * One gate, always: the nominated doctor signs, then an admin decides. The
 * report body is assembled exactly once — at issue time — and every state
 * change is audited.
 */
class PatientReportService
{
    public function __construct(
        private readonly AuditService $audit,
        private readonly PatientReportAssembler $assembler,
        private readonly PatientReportRenderer $renderer,
    ) {}

    /**
     * Create the request and send it straight to the nominated doctor.
     *
     * [$doctor] is required. It used to be optional, falling back to whichever
     * provider the patient's assignments happened to rank first — fine while a
     * signature was one gate among two, wrong now that it is the only one. A
     * patient with a GP and two specialists has no obvious signer, and picking
     * for the admin silently sends a cardiology report to a dermatologist.
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
        User $doctor,
    ): PatientReportRequest {
        $sections = $this->normalizeSections($sections);

        $request = PatientReportRequest::create([
            'patient_user_id' => $patient->id,
            'requested_by_user_id' => $actor->id,
            'doctor_user_id' => $doctor->id,
            'title' => $title,
            'purpose' => $purpose,
            'recipient' => $recipient,
            'sections' => $sections,
            'consent_required' => false,
            'signature_required' => true,
            'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE,
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
                'doctor_user_id' => $doctor->id,
            ],
        );

        $this->notifyDoctor($request->fresh());

        return $request->fresh();
    }

    /**
     * Doctor sign-off — the single authorisation for issuing a report.
     *
     * Nothing is disclosed by signing. The signature says the content is
     * accurate and appropriate to send; an admin still has to issue it, and
     * can send it back instead.
     */
    public function sign(
        User $doctor,
        PatientReportRequest $request,
        string $signatureName,
        ?string $note,
    ): void {
        $wasReturned = $request->returned_at !== null;

        $request->update([
            'doctor_user_id' => $doctor->id,
            'signed_at' => now(),
            'signature_name' => $signatureName,
            'signature_note' => $note,
            'status' => PatientReportRequest::STATUS_SIGNED,
            // The return trip is over. `return_count` deliberately survives —
            // it is the history of how many times this report came back, and
            // clearing it would hide exactly the thing worth seeing.
            'returned_at' => null,
            'return_note' => null,
            // A fresh signature is a fresh decision for the admin to make.
            'under_review_at' => null,
            'under_review_note' => null,
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
                'title' => $wasReturned ? 'Report re-signed' : 'Report signed',
                'body' => 'Dr. '.$doctor->fullName()
                    .($wasReturned ? ' re-signed "' : ' signed "').$request->title
                    .'". Review it and issue it to the patient.',
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
     * Admin sends a signed report back to the doctor for a correction.
     *
     * The alternative was revoking, which throws away the patient's consent
     * along with the draft and means re-asking someone who has already said
     * yes. Consent is to a *set of sections*, and a returned report keeps the
     * same sections — so it survives the round trip untouched, while the
     * signature does not: it was given against content that is about to
     * change, and has to be given again against the corrected version.
     *
     * @param  string  $note  what the doctor needs to change; shown to them
     */
    public function returnForRework(
        User $actor,
        PatientReportRequest $request,
        string $note,
    ): void {
        $request->update([
            'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE,
            'signed_at' => null,
            'signature_name' => null,
            'signature_note' => null,
            'returned_at' => now(),
            'returned_by_user_id' => $actor->id,
            'return_note' => $note,
            'return_count' => (int) $request->return_count + 1,
            'under_review_at' => null,
            'under_review_note' => null,
        ]);

        $request->refresh();

        $this->audit->record(
            $actor,
            'report.returned_for_review',
            $request->patient?->fullName().' — '.$request->title,
            'activity',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'doctor_user_id' => $request->doctor_user_id,
                'note' => $note,
                'return_count' => $request->return_count,
            ],
        );

        if ($request->doctor_user_id) {
            AppNotification::create([
                'user_id' => $request->doctor_user_id,
                'kind' => 'consent',
                'title' => 'Report sent back for changes',
                'body' => $actor->fullName().' returned "'.$request->title
                    .'" for '.($request->patient?->fullName() ?? 'a patient')
                    .'. '.$note.' Your signature was cleared — review the '
                    .'corrected report and sign again.',
                'action_route' => '/doctor/reports',
                'read' => false,
            ]);
        }
    }

    /**
     * Park a signed report an admin has read but is not ready to issue.
     *
     * Without it the queue could not tell a report nobody had opened from one
     * an admin had read, questioned, and left while they checked something —
     * so a second admin would open it cold and redo the same reading, or worse,
     * issue what the first had doubts about. Purely an annotation: the report
     * stays signed and issuable, and issuing it needs no un-parking step.
     */
    public function markUnderReview(
        User $actor,
        PatientReportRequest $request,
        ?string $note,
    ): void {
        $request->update([
            'status' => PatientReportRequest::STATUS_UNDER_REVIEW,
            'under_review_at' => now(),
            'under_review_note' => $note,
        ]);

        $this->audit->record(
            $actor,
            'report.under_review',
            $request->patient?->fullName().' — '.$request->title,
            'activity',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'note' => $note,
            ],
        );
    }

    /**
     * Reject a report and delete it.
     *
     * Only reachable before issue, which is what makes deletion the right
     * answer rather than a destroyed record: nothing was disclosed, so there is
     * no disclosure to preserve — only the fact that a report was asked for and
     * refused, and that belongs in the audit trail, which outlives the row. A
     * rejected request left sitting in the list as a tombstone is noise in a
     * queue admins work daily.
     *
     * The audit entry carries the whole request, because after this call the
     * row is the only other place that information existed.
     */
    public function reject(User $actor, PatientReportRequest $request, string $reason): void
    {
        $doctorId = $request->doctor_user_id;
        $title = $request->title;
        $patientName = $request->patient?->fullName();
        $wasSigned = $request->signed_at !== null;

        $this->audit->record(
            $actor,
            'report.rejected',
            $patientName.' — '.$title,
            'security',
            [
                'patient_user_id' => $request->patient_user_id,
                'target_user_id' => $request->patient_user_id,
                'report_request_id' => $request->id,
                'title' => $title,
                'purpose' => $request->purpose,
                'recipient' => $request->recipient,
                'sections' => $request->sections,
                'doctor_user_id' => $doctorId,
                'signature_name' => $request->signature_name,
                'signed_at' => $request->signed_at?->toIso8601String(),
                'requested_by_user_id' => $request->requested_by_user_id,
                'reason' => $reason,
            ],
        );

        $request->delete();

        // A doctor who put their name to it is told it was thrown out. The
        // patient is not: nothing left mCare, and telling them a report they
        // never knew about was cancelled is noise, not transparency.
        if ($doctorId && $wasSigned) {
            AppNotification::create([
                'user_id' => $doctorId,
                'kind' => 'consent',
                'title' => 'Signed report rejected',
                'body' => $actor->fullName().' rejected "'.$title.'" for '
                    .($patientName ?? 'a patient')
                    .', which you signed, and deleted the request. Reason: '
                    .$reason,
                'action_route' => '/doctor/reports',
                'read' => false,
            ]);
        }
    }

    /**
     * Freeze the signed-off sections into the snapshot. This is the only place
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

        // Issuing hands the report to the recipient; the patient is entitled to
        // their own copy of it in the same place as everything else in their
        // record, not only a line on a consent screen they have to go looking
        // for. Filing it here is what makes "the admin approved it" and "the
        // patient has it" the same event.
        $this->fileCopyForPatient($actor, $request, $document);

        // The patient is always told when their record actually went out, and
        // told by whom it was signed — with the consent step gone, that is the
        // transparency they have left, so it goes in the message rather than
        // being something they must open the report to discover.
        AppNotification::create([
            'user_id' => $request->patient_user_id,
            'kind' => 'consent',
            'title' => 'Report issued from your record',
            'body' => '"'.$request->title.'" was issued'
                .($request->recipient ? ' to '.$request->recipient : '')
                .' covering '.count($request->sections ?? []).' section'
                .(count($request->sections ?? []) === 1 ? '' : 's').' of your record'
                .($request->signature_name ? ', signed by '.$request->signature_name : '')
                .'. A copy is in your documents.',
            'action_route' => '/patient/report-consents',
            'read' => false,
        ]);

        // …and told outside the app as well. An in-app badge only reaches a
        // patient who happens to open mCare; a disclosure of their record to a
        // third party is the one event they should not have to go looking for.
        $this->emailPatient($request);

        return $document;
    }

    /**
     * Emails the patient that a report went out.
     *
     * Notice only — the mail names what was disclosed and to whom, never the
     * clinical content, which stays behind their login. Never throws: the
     * disclosure has already happened and been audited, and a bounced
     * notification must not report the issue itself as having failed.
     */
    private function emailPatient(PatientReportRequest $request): void
    {
        try {
            $patient = $request->patient;
            $email = trim((string) ($patient?->email ?? ''));
            if ($patient === null || $email === '') {
                return;
            }

            MailDispatcher::send($email, new ReportIssuedMail(
                patientName: (string) $patient->first_name,
                title: (string) $request->title,
                reference: 'RPT-'.$request->id,
                sections: array_values((array) ($request->sections ?? [])),
                recipient: $request->recipient,
                purpose: $request->purpose,
                signedBy: $request->signature_name,
                issuedAt: now()->format('j M Y, H:i'),
                frontendUrl: rtrim((string) config('mcare.frontend_url'), '/'),
            ), ['report_request_id' => $request->id]);
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Withdraw a report that has already been issued.
     *
     * The row is never deleted here, and that is the whole difference from
     * {@see reject()}: this report went out. Something exists in the world that
     * a recipient may act on and the patient holds a copy of, so the record has
     * to say it existed and was withdrawn. Deleting it would erase the evidence
     * of a disclosure rather than undo one — which is not in anyone's power.
     */
    public function revoke(User $actor, PatientReportRequest $request, string $reason): void
    {
        $wasIssued = $request->issued_at !== null;
        $signedAt = $request->signed_at;

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
                'was_issued' => $wasIssued,
            ],
        );

        // A doctor who signed is entitled to know the report was discarded or
        // pulled back — their name is on it either way.
        if ($request->doctor_user_id && $signedAt !== null) {
            AppNotification::create([
                'user_id' => $request->doctor_user_id,
                'kind' => 'consent',
                'title' => $wasIssued
                    ? 'Issued report revoked'
                    : 'Signed report discarded',
                'body' => $actor->fullName()
                    .($wasIssued ? ' revoked "' : ' discarded "').$request->title
                    .'" for '.($request->patient?->fullName() ?? 'a patient')
                    .', which you signed. Reason: '.$reason,
                'action_route' => '/doctor/reports',
                'read' => false,
            ]);
        }

        // The patient only hears about it when something actually went out — a
        // discarded draft was never disclosed and is not theirs to be alarmed
        // by, but a report already sitting in their documents is.
        if ($wasIssued) {
            AppNotification::create([
                'user_id' => $request->patient_user_id,
                'kind' => 'consent',
                'title' => 'A report from your record was revoked',
                'body' => '"'.$request->title.'" was withdrawn'
                    .($request->recipient ? ' from '.$request->recipient : '')
                    .'. Reason: '.$reason
                    .' Your copy stays in your documents, marked as revoked.',
                'action_route' => '/patient/report-consents',
                'read' => false,
            ]);
        }
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
    /**
     * Files the issued report into the patient's own documents.
     *
     * Rendered from the frozen snapshot, so this copy and the one the
     * recipient was sent are the same document, and it stays correct after the
     * underlying record moves on.
     *
     * Never throws. Issuing has already happened and been audited by the time
     * this runs; failing here would report the disclosure as failed when it
     * did not, and leave staff unsure whether to issue again.
     *
     * @param  array<string, mixed>  $document
     */
    private function fileCopyForPatient(
        User $actor,
        PatientReportRequest $request,
        array $document,
    ): void {
        try {
            // Re-issue is refused upstream, but a retry after a partial failure
            // must not leave the patient with two copies of one report.
            $existing = MedicalDocument::where('issued_report_id', $request->id)->exists();
            if ($existing) {
                return;
            }

            $stored = MedicalDocumentFiles::storeGeneratedFile(
                (int) $request->patient_user_id,
                $request->title,
                $this->renderer->toHtml($document, null, [
                    'status' => 'issued',
                    'reference' => 'RPT-'.$request->id,
                ]),
            );

            $filed = MedicalDocument::create([
                'user_id' => $request->patient_user_id,
                'title' => $request->title,
                'category' => 'other',
                'file_type' => 'other',
                'storage_path' => $stored['path'],
                'size_bytes' => $stored['size'],
                'description' => 'Report issued'
                    .($request->recipient ? ' to '.$request->recipient : '')
                    .' on '.now()->format('j M Y').'.',
                'uploaded_by' => 'mCare · '.$actor->fullName(),
                'uploaded_at' => now(),
                'source' => MedicalDocument::SOURCE_REPORT,
                'issued_report_id' => $request->id,
            ]);

            DocumentDelivery::notifyOwner($filed, 'mCare');
        } catch (\Throwable $e) {
            report($e);
        }
    }

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

}
