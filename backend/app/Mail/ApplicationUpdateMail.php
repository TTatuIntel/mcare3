<?php

namespace App\Mail;

use App\Models\User;
use App\Support\MailContent;

/**
 * A decision, or a question, about an application that has not been approved.
 *
 * Both used to be written only as in-app notifications — to an account that
 * cannot sign in until it is approved. The applicant was told nothing, and
 * the request for more information waited in an inbox they had no way to
 * open. Email is the only channel that reaches them at this stage.
 */
class ApplicationUpdateMail extends BrandedMail
{
    public const KIND_INFO_REQUESTED = 'info_requested';

    public const KIND_REJECTED = 'rejected';

    public function __construct(
        public User $user,
        public string $kind,
        public string $message,
        public string $frontendUrl,
    ) {}

    protected function subjectLine(): string
    {
        return $this->kind === self::KIND_REJECTED
            ? 'Your mCare application was not approved'
            : 'More information needed for your mCare application';
    }

    protected function body(): MailContent
    {
        $role = $this->user->roleToClient();
        $rejected = $this->kind === self::KIND_REJECTED;

        $content = MailContent::make()
            ->eyebrow('Application update')
            ->heading($rejected ? 'Application not approved' : 'We need a little more information')
            ->preheader($rejected
                ? "Your application to join mCare as {$role} was not approved."
                : "An administrator needs more information before deciding your mCare application.")
            ->greeting($this->user->first_name);

        if ($rejected) {
            $content
                ->paragraph("Your application to join mCare as {$role} has not been approved.")
                ->quote($this->message)
                ->callout(
                    'If you believe this was decided in error, reply to this email and an administrator will look at it again.',
                    MailContent::TONE_INFO,
                );
        } else {
            $content
                ->paragraph("An mCare administrator needs more information before your application to join as {$role} can be decided.")
                ->subheading('What is needed')
                ->quote($this->message)
                ->paragraph('Reply to this email with the details above and your application will continue.')
                ->callout(
                    'Your account stays open in the meantime — there is nothing else for you to do.',
                    MailContent::TONE_SUCCESS,
                );
        }

        return $content->button('Open mCare', rtrim($this->frontendUrl, '/'));
    }
}
