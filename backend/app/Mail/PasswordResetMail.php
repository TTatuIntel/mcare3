<?php

namespace App\Mail;

use App\Models\User;
use App\Support\MailContent;

/**
 * Account recovery by email, carrying both routes in one message.
 *
 * The reader gets a one-tap link *and* a 6-digit code. Which one they use is
 * down to where they opened the mail: the link works when email and app are on
 * the same device, and the code is what someone reads off a laptop and types
 * into a phone. Sending only the link stranded that second reader, who is the
 * common case on a shared clinic computer.
 */
class PasswordResetMail extends BrandedMail
{
    public function __construct(
        public User $user,
        public string $resetToken,
        public string $frontendUrl,
        /** Six-digit alternative to the link; null when only a link was minted. */
        public ?string $code = null,
        public int $expiresInMinutes = 60,
    ) {}

    protected function subjectLine(): string
    {
        return $this->code === null
            ? 'Reset your mCare password'
            : "{$this->code} is your mCare password reset code";
    }

    public function resetUrl(): string
    {
        return rtrim($this->frontendUrl, '/')
            .'/reset-password?email='.urlencode($this->user->email)
            .'&token='.urlencode($this->resetToken);
    }

    protected function body(): MailContent
    {
        $content = MailContent::make()
            ->eyebrow('Account security')
            ->heading('Reset your password')
            ->preheader($this->code === null
                ? "Choose a new mCare password. This link expires in {$this->expiresInMinutes} minutes."
                : "Your mCare reset code is {$this->code}. It expires in {$this->expiresInMinutes} minutes.")
            ->greeting($this->user->first_name)
            ->paragraph('We received a request to reset the password on your mCare account. Choose whichever of these is easier — both do the same thing.')
            ->subheading('1. Open this link on this device')
            ->button('Choose a new password', $this->resetUrl());

        if ($this->code !== null) {
            $content
                ->subheading('2. Or type this code into the mCare app')
                ->code($this->code, 'Password reset code')
                ->paragraph('In the app, choose Forgot password, enter '.$this->user->email.', then enter the code above.');
        }

        return $content
            ->facts([
                'Account' => $this->user->email,
                'Expires in' => $this->expiresInMinutes.' minutes',
                'Uses' => 'Single use',
            ])
            ->callout(
                "Resetting your password signs you out on every device.\nIf you did not request this, you can safely ignore this email — your password stays exactly as it is.",
                MailContent::TONE_WARNING,
                'Before you continue',
            );
    }
}
