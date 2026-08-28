<?php

namespace App\Mail;

use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * A decision, or a question, about an application that has not been approved.
 *
 * Both used to be written only as in-app notifications — to an account that
 * cannot sign in until it is approved. The applicant was told nothing, and
 * the request for more information waited in an inbox they had no way to
 * open. Email is the only channel that reaches them at this stage.
 */
class ApplicationUpdateMail extends Mailable
{
    use Queueable, SerializesModels;

    public const KIND_INFO_REQUESTED = 'info_requested';

    public const KIND_REJECTED = 'rejected';

    public function __construct(
        public User $user,
        public string $kind,
        public string $message,
        public string $frontendUrl,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: $this->kind === self::KIND_REJECTED
                ? 'Your mCare application was not approved'
                : 'More information needed for your mCare application',
        );
    }

    public function content(): Content
    {
        return new Content(
            text: 'mail.application-update-text',
        );
    }
}
