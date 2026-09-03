<?php

namespace App\Mail;

use App\Support\MailContent;
use App\Support\PatientReportSections;

/**
 * Tells a patient, by email, that part of their record has been disclosed.
 *
 * Issuing already wrote an in-app notification and filed a copy in the
 * patient's documents — both of which require the patient to open the app to
 * discover that a disclosure happened at all. A report goes to an insurer, an
 * employer, another clinic; if the patient disagrees with it the window to say
 * so is short, and an unread badge is not notice.
 *
 * The mail deliberately carries no clinical content: what was disclosed, to
 * whom, by whose signature, and where to read it — never the readings
 * themselves. Email is not a channel this application controls, and the full
 * document stays behind the patient's own login.
 */
class ReportIssuedMail extends BrandedMail
{
    /**
     * @param  list<string>  $sections  Section keys covered by the report.
     */
    public function __construct(
        public string $patientName,
        public string $title,
        public string $reference,
        public array $sections,
        public ?string $recipient,
        public ?string $purpose,
        public ?string $signedBy,
        public string $issuedAt,
        public string $frontendUrl,
    ) {}

    protected function subjectLine(): string
    {
        return 'A report from your mCare record was issued';
    }

    protected function body(): MailContent
    {
        $count = count($this->sections);
        $released = $this->recipient ?: 'the requesting party';

        $content = MailContent::make()
            ->eyebrow('Care record')
            ->heading('A report from your record was issued')
            ->preheader('"'.$this->title.'" was released to '.$released.'. A copy is in your mCare documents.')
            ->greeting($this->patientName)
            ->paragraph(
                'A report drawn from your mCare record has been signed by a '
                .'clinician and released. This message is your notice that it '
                .'happened — the report itself stays in your account.',
            )
            ->document($this->title, [
                'Reference' => $this->reference,
                'Released to' => $this->recipient,
                'Purpose' => $this->purpose,
                'Signed by' => $this->signedBy,
                'Issued' => $this->issuedAt,
            ], 'Issued')
            ->bullets(
                array_map(
                    static fn (string $key) => PatientReportSections::label($key),
                    $this->sections,
                ),
                $count === 1
                    ? 'The one section of your record it covers'
                    : 'The '.$count.' sections of your record it covers',
            )
            ->paragraph(
                'Nothing outside those sections was included. The full report — '
                .'exactly as it was sent — is saved in your documents.',
            );

        if ($this->frontendUrl !== '') {
            $content->button('Open my documents', $this->frontendUrl.'/patient/documents');
        }

        return $content
            ->callout(
                'If you did not expect this, or anything in the report looks '
                .'wrong, contact your care team straight away. A report that '
                .'has gone out can be withdrawn, and the withdrawal is recorded.',
                MailContent::TONE_WARNING,
                'Something not right?',
            )
            ->footerNote(
                'You are receiving this because a report was issued from your '
                .'mCare record. Notices about disclosures from your own record '
                .'cannot be turned off.',
            );
    }
}
