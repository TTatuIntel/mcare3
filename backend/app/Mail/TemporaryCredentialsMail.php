<?php

namespace App\Mail;

use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * The one message that carries a temporary password to the person it belongs
 * to.
 *
 * Both moments an administrator sets someone's password — approving their
 * application, or resetting it for them — used to leave the password on the
 * administrator's screen to be relayed by hand. This delivers it to the
 * address the account was opened with, and says plainly that it only lasts
 * until the first sign-in.
 */
class TemporaryCredentialsMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public User $user,
        public string $temporaryPassword,
        public string $frontendUrl,
        /** True when this follows an approval, false for an administrator reset. */
        public bool $approved,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: $this->approved
                ? 'Your mCare account is approved'
                : 'Your mCare password was reset',
        );
    }

    public function content(): Content
    {
        return new Content(
            text: 'mail.temporary-credentials-text',
        );
    }
}
