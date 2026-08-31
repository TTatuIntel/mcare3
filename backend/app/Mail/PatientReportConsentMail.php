<?php

namespace App\Mail;

use App\Models\PatientReportRequest;
use App\Models\User;
use App\Support\MailContent;

/**
 * Asks the patient to approve disclosure of specific sections of their
 * record. Carries both the one-time code (read back to staff over the phone)
 * and the approval link (tapped directly).
 */
class PatientReportConsentMail extends BrandedMail
{
    /**
     * @param  list<string>  $sectionLabels
     */
    public function __construct(
        public User $patient,
        public PatientReportRequest $reportRequest,
        public string $code,
        public string $approvalUrl,
        public array $sectionLabels,
    ) {}

    protected function subjectLine(): string
    {
        return 'Approve sharing of your mCare record';
    }

    protected function body(): MailContent
    {
        return MailContent::make()
            ->eyebrow('Care record')
            ->heading('A report from your record needs your approval')
            ->preheader("Your approval code is {$this->code}. Nothing is shared unless you approve it.")
            ->greeting($this->patient->first_name)
            ->paragraph('mCare staff have asked to prepare a report from your health record. Nothing is shared unless you approve it.')
            ->facts([
                'Purpose' => $this->reportRequest->purpose,
                'Would be shared with' => $this->reportRequest->recipient,
                'Approval expires' => $this->reportRequest->consent_expires_at?->format('d M Y, H:i'),
            ], 'Request details')
            ->bullets($this->sectionLabels, 'The report would include only these parts of your record')
            ->code($this->code, 'One-time approval code')
            ->paragraph('Read this code back to the mCare staff member who called you, or approve it yourself under "Sharing requests".')
            ->button('Review and approve', $this->approvalUrl)
            ->callout(
                'For your safety this link asks you to sign in first — nobody can approve sharing of your record just by opening your email.',
                MailContent::TONE_INFO,
                'Why you are asked to sign in',
            )
            ->callout(
                'If you did not expect this request, ignore this email and contact mCare support.',
                MailContent::TONE_WARNING,
            );
    }
}
