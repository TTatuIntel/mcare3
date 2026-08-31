<?php

namespace App\Mail;

use App\Models\User;
use App\Support\MailContent;

class UserInviteMail extends BrandedMail
{
    public function __construct(
        public User $user,
        public string $inviteToken,
        public string $frontendUrl,
    ) {}

    protected function subjectLine(): string
    {
        return "You're invited to mCare";
    }

    protected function body(): MailContent
    {
        $role = $this->user->roleToClient();

        return MailContent::make()
            ->eyebrow('Invitation')
            ->heading('Join mCare')
            ->preheader("You have been invited to join mCare as {$role}. The invite expires in 7 days.")
            ->greeting($this->user->first_name)
            ->paragraph("You have been invited to join mCare as {$role}.")
            ->paragraph('Open the mCare app, choose "Accept invite", and enter the token below to set your password.')
            ->code($this->inviteToken, 'Invite token')
            ->button('Open mCare', rtrim($this->frontendUrl, '/'))
            ->callout('This invite expires in 7 days. After that an administrator will need to send you a new one.', MailContent::TONE_INFO);
    }
}
