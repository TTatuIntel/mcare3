<?php

namespace App\Mail;

use App\Support\MailContent;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * The single template every mCare email is rendered through.
 *
 * Subclasses say what the message is — a subject line and a {@see MailContent}
 * block list — and inherit the branded HTML shell, the matching plain-text
 * alternative, the reply-to address, and the footer. Six mailables previously
 * carried six hand-written text views that drifted apart in tone, had no HTML
 * part at all, and repeated the same sign-off six times.
 *
 * Every message goes out multipart: clients that render HTML get the branded
 * version, and text-only clients and spam filters get a complete plain-text
 * copy of exactly the same content.
 */
abstract class BrandedMail extends Mailable
{
    use Queueable, SerializesModels;

    /** Human-readable subject. Keep under ~60 characters so it is not clipped. */
    abstract protected function subjectLine(): string;

    /** The body, described as blocks rather than markup. */
    abstract protected function body(): MailContent;

    public function envelope(): Envelope
    {
        $replyTo = trim((string) config('mail.reply_to.address', ''));

        return new Envelope(
            subject: $this->subjectLine(),
            replyTo: $replyTo === '' ? [] : [
                new Address($replyTo, (string) config('mail.reply_to.name', config('app.name'))),
            ],
            // Groups every message about one account into a single inbox
            // thread rather than a stack of near-identical subjects.
            using: [fn ($message) => $message->getHeaders()->addTextHeader(
                'X-Entity-Ref-ID',
                static::class,
            )],
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.layout',
            text: 'mail.layout-text',
            with: $this->body()->toArray() + [
                'appName' => (string) config('app.name', 'mCare'),
                'frontendUrl' => rtrim((string) config('mcare.frontend_url'), '/'),
                // Falls through no-reply -> reply-to -> from, so the footer
                // never prints an address nobody reads.
                'supportEmail' => (string) (config('mail.support_address')
                    ?: config('mail.reply_to.address')
                    ?: config('mail.from.address')),
            ],
        );
    }
}
