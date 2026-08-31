<?php

namespace App\Support;

use Illuminate\Mail\Mailable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * The single send path for application mail.
 *
 * Two things were wrong with calling Mail::to()->send() at each site. Every
 * caller wrapped it in `try { … } catch { report($e); }`, so a rejected
 * credential or an exhausted daily quota produced a stack trace nobody read
 * while the API cheerfully answered "a code was sent" — the user waited at an
 * empty inbox with no way to tell that the send had failed. And nothing
 * recorded that a message went out at all, so "did the OTP leave the server?"
 * could not be answered from the logs.
 *
 * Sending stays synchronous on purpose. A one-time code is worth nothing five
 * minutes later, and queueing it makes delivery depend on a worker being up;
 * the SMTP timeout in config/mail.php is what bounds the request instead.
 */
final class MailDispatcher
{
    /**
     * Sends now and says whether the transport accepted the message.
     *
     * Never throws: a failed notification must not turn into a 500 on a
     * request that has already changed state (a token minted, a user approved).
     */
    public static function send(string $to, Mailable $mailable, array $context = []): bool
    {
        $mailer = (string) config('mail.default');
        $log = [
            'mailable' => class_basename($mailable),
            'to' => self::maskEmail($to),
            'mailer' => $mailer,
        ] + $context;

        try {
            Mail::to($to)->send($mailable);
        } catch (\Throwable $e) {
            report($e);
            Log::error('Email delivery failed', $log + ['error' => $e->getMessage()]);

            return false;
        }

        // `log` and `array` transports accept everything and deliver nothing.
        // Saying so here is the difference between a developer trusting a
        // green result and hunting an email that was never sent.
        if (in_array($mailer, ['log', 'array', 'null'], true)) {
            Log::warning('Email was not delivered: mailer is not a real transport', $log);

            return false;
        }

        Log::info('Email delivered to transport', $log);

        return true;
    }

    /** Recipients are masked in logs; an inbox address is personal data. */
    private static function maskEmail(string $email): string
    {
        $at = strpos($email, '@');
        if ($at === false || $at === 0) {
            return str_repeat('*', strlen($email));
        }

        $name = substr($email, 0, $at);
        $domain = substr($email, $at);

        return strlen($name) <= 2
            ? str_repeat('*', strlen($name)).$domain
            : $name[0].str_repeat('*', strlen($name) - 2).$name[-1].$domain;
    }
}
