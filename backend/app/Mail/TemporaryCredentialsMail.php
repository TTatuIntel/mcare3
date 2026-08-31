<?php

namespace App\Mail;

use App\Models\User;
use App\Support\MailContent;

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
class TemporaryCredentialsMail extends BrandedMail
{
    public function __construct(
        public User $user,
        public string $temporaryPassword,
        public string $frontendUrl,
        /** True when this follows an approval, false for an administrator reset. */
        public bool $approved,
    ) {}

    protected function subjectLine(): string
    {
        return $this->approved
            ? 'Your mCare account is approved'
            : 'Your mCare password was reset';
    }

    protected function body(): MailContent
    {
        $role = $this->user->roleToClient();

        return MailContent::make()
            ->eyebrow($this->approved ? 'Application approved' : 'Account security')
            ->heading($this->approved ? 'Your account is ready' : 'Your password was reset')
            ->preheader($this->approved
                ? "Sign in to mCare as {$role} with the temporary password inside."
                : 'An administrator issued you a temporary mCare password.')
            ->greeting($this->user->first_name)
            ->paragraph($this->approved
                ? "Your application to join mCare as {$role} has been approved. Sign in with the details below to finish setting up your account."
                : 'An mCare administrator has reset the password on your account. Sign in with the details below to choose a new one.')
            ->facts([
                'Email' => $this->user->email,
                'Temporary password' => $this->temporaryPassword,
                'Role' => $role,
            ], 'Sign-in details')
            ->button('Sign in to mCare', rtrim($this->frontendUrl, '/'), MailContent::TONE_SUCCESS)
            ->paragraph('You will be asked to choose your own password as soon as you sign in. The temporary one stops working at that point, so it cannot be reused.')
            ->callout(
                'If you were not expecting this email, contact your mCare administrator straight away and do not share the password above with anyone.',
                MailContent::TONE_DANGER,
                'Keep this password to yourself',
            );
    }
}
