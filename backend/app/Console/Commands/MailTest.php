<?php

namespace App\Console\Commands;

use App\Mail\DeliveryTestMail;
use App\Support\MailConfiguration;
use App\Support\MailDispatcher;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;

/**
 * Sends one real email and reports exactly what the transport said.
 *
 * This deliberately does not go through {@see MailDispatcher},
 * which swallows the exception so a failed notification cannot 500 a request
 * that already changed state. That is right for production traffic and wrong
 * for a diagnostic: the SMTP response *is* the answer here, so the send is
 * performed inline and the exception printed. Everything else — the mailable,
 * the transport, the configured addresses — is identical to what production
 * uses, so a pass here means production sends.
 */
class MailTest extends Command
{
    protected $signature = 'mcare:mail-test {email : Inbox to deliver the test message to}';

    protected $description = 'Send a real test email and report the transport response';

    public function handle(): int
    {
        $to = (string) $this->argument('email');
        if (! filter_var($to, FILTER_VALIDATE_EMAIL)) {
            $this->error("Not a valid email address: {$to}");

            return self::FAILURE;
        }

        $mailer = (string) config('mail.default');
        $from = (string) config('mail.from.address');

        $this->line("Mailer .......... {$mailer}");
        $this->line('Host ............ '.(string) config("mail.mailers.{$mailer}.host", '—'));
        $this->line("From ............ {$from}");
        $this->line("To .............. {$to}");
        $this->newLine();

        // `log` and `array` accept every message and deliver none of them.
        // Reporting success here is how an operator ends up hunting an email
        // that was never sent.
        if (in_array($mailer, ['log', 'array', 'null'], true)) {
            $this->error("MAIL_MAILER is '{$mailer}', which does not deliver anything.");
            $this->line('Set MAIL_MAILER=smtp in .env and configure a transactional provider.');

            return self::FAILURE;
        }

        $configurationIssue = MailConfiguration::credentialIssue($mailer);
        if ($configurationIssue !== null) {
            $this->error('DELIVERY BLOCKED');
            $this->line($configurationIssue.'.');

            return self::FAILURE;
        }

        if ($from === '' || str_contains($from, 'example.com')) {
            $this->warn("MAIL_FROM_ADDRESS is '{$from}' — most providers reject an unverified sender.");
        }

        $this->line('Sending…');

        try {
            Mail::to($to)->send(new DeliveryTestMail(
                sentAt: now()->toDayDateTimeString().' UTC',
                transport: $mailer,
                environment: (string) config('app.env'),
            ));
        } catch (\Throwable $e) {
            $this->newLine();
            $this->error('DELIVERY FAILED');
            // The provider's own words are the actionable part. A daily cap, an
            // unverified sender and a bad key are three different fixes and the
            // response text is what tells them apart.
            $this->line(str_replace(["\r\n", "\r", "\n"], ' ', $e->getMessage()));

            return self::FAILURE;
        }

        $this->newLine();
        $this->info("DELIVERED — the transport accepted the message for {$to}.");
        $this->line('Check that inbox (and its spam folder). If it never arrives, the');
        $this->line('provider accepted then dropped it — check the provider dashboard.');

        return self::SUCCESS;
    }
}
