<?php

namespace App\Mail;

use App\Support\MailContent;

/**
 * A real message, sent down the real transport, to prove delivery works.
 *
 * The readiness audit's SMTP probe only opens a connection and authenticates.
 * That is enough to catch a wrong password, but a provider can accept the
 * login and still refuse the message a moment later — Gmail answers AUTH
 * happily and then rejects DATA with "550 Daily user sending limit exceeded"
 * once the account is capped. The audit read PASS the whole time nobody was
 * receiving mail. Only a message that travels the full path proves the path.
 *
 * It renders through the same branded layout as every other mailable, so a
 * successful test also confirms the template, the from/reply-to addresses and
 * the footer are configured — not merely that a socket opened.
 */
class DeliveryTestMail extends BrandedMail
{
    public function __construct(
        /** Distinguishes one test from the last when several are sent. */
        public string $sentAt,
        public string $transport,
        public string $environment,
    ) {}

    protected function subjectLine(): string
    {
        return 'mCare email delivery test';
    }

    protected function body(): MailContent
    {
        return MailContent::make()
            ->eyebrow('Configuration check')
            ->heading('Email delivery is working')
            ->preheader('If you can read this, mCare can deliver mail to real inboxes.')
            ->paragraph(
                'This message was sent by the mcare:mail-test command. Receiving it '
                .'confirms the whole delivery path — transport, credentials, sender '
                .'address and template — is working end to end.'
            )
            ->facts([
                'Mailer' => $this->transport,
                'Environment' => $this->environment,
                'Sent at' => $this->sentAt,
            ], 'What was tested')
            ->callout(
                'Nothing about your account changed. This is a diagnostic message '
                .'and it is safe to delete.',
                MailContent::TONE_SUCCESS,
                'No action needed',
            );
    }
}
