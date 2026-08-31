<?php

namespace App\Mail;

use App\Models\User;
use App\Support\MailContent;

/**
 * Address verification, carrying both routes in one message.
 *
 * The reader gets a one-tap link *and* a 6-digit code, exactly as password
 * recovery does. Which one they use depends on where they opened the mail:
 * the link finishes it when mail and app are on the same device, and the code
 * is what someone reads off a clinic desktop and types into their phone.
 * Sending only the code stranded that second reader with a transcription job;
 * sending only the link stranded the first with nothing to type.
 */
class EmailVerificationMail extends BrandedMail
{
    public function __construct(
        public User $user,
        public string $code,
        /** One-tap alternative to the code; null when only a code was minted. */
        public ?string $verifyUrl = null,
        public int $expiresInMinutes = 15,
    ) {}

    protected function subjectLine(): string
    {
        return "{$this->code} is your mCare verification code";
    }

    protected function body(): MailContent
    {
        $content = MailContent::make()
            ->eyebrow('Account security')
            ->heading('Verify your email address')
            ->preheader("Your mCare verification code is {$this->code}. It expires in {$this->expiresInMinutes} minutes.")
            ->greeting($this->user->first_name)
            ->paragraph(
                "Confirm that {$this->user->email} belongs to you. Either of these "
                .'finishes it — pick whichever is easier from where you are reading this.'
            );

        if ($this->verifyUrl !== null) {
            $content
                ->subheading('1. Tap to verify on this device')
                ->button('Verify my email', $this->verifyUrl)
                ->subheading('2. Or type this code into the mCare app');
        }

        return $content
            ->code($this->code, 'Verification code')
            ->paragraph("The code expires in {$this->expiresInMinutes} minutes and can only be used once.")
            ->facts([
                'Account' => $this->user->email,
                'Expires in' => $this->expiresInMinutes.' minutes',
                'Uses' => 'Single use',
            ])
            ->callout(
                'If you did not ask to verify this address, ignore this email and contact an mCare administrator — someone may have entered your address by mistake.',
                MailContent::TONE_WARNING,
                'Did not request this?',
            );
    }
}
