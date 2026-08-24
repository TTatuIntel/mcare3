<?php

namespace App\Mail;

use App\Models\PatientReportRequest;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Asks the patient to approve disclosure of specific sections of their
 * record. Carries both the one-time code (read back to staff over the phone)
 * and the approval link (tapped directly).
 */
class PatientReportConsentMail extends Mailable
{
    use Queueable, SerializesModels;

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

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Approve sharing of your mCare record',
        );
    }

    public function content(): Content
    {
        return new Content(
            text: 'mail.patient-report-consent-text',
        );
    }
}
