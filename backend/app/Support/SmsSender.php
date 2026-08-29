<?php

namespace App\Support;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Outbound SMS for account-recovery codes.
 *
 * Driver is chosen by SMS_DRIVER. `twilio` posts to the real Messages API;
 * `log` writes the message to the application log so local development can
 * read the OTP without a paid gateway. An unconfigured `twilio` driver falls
 * back to `log` rather than throwing — recovery must never 500 because a
 * gateway credential is missing.
 */
class SmsSender
{
    /** Returns true when the message was handed to a real gateway. */
    public function send(string $to, string $message): bool
    {
        $number = $this->normalize($to);
        if ($number === null) {
            return false;
        }

        $driver = (string) config('services.sms.driver', 'log');

        if ($driver === 'twilio' && $this->twilioConfigured()) {
            return $this->sendViaTwilio($number, $message);
        }

        Log::info('SMS (log driver)', ['to' => $number, 'message' => $message]);

        return false;
    }

    /**
     * E.164 normalisation. Numbers stored without a country code are prefixed
     * with SMS_DEFAULT_COUNTRY_CODE; a leading local trunk `0` is dropped.
     */
    public function normalize(?string $raw): ?string
    {
        $digits = preg_replace('/[^0-9+]/', '', (string) $raw) ?? '';
        if ($digits === '') {
            return null;
        }

        if (str_starts_with($digits, '+')) {
            $digits = '+'.preg_replace('/[^0-9]/', '', substr($digits, 1));

            return strlen($digits) >= 8 ? $digits : null;
        }

        $digits = preg_replace('/[^0-9]/', '', $digits) ?? '';
        if ($digits === '') {
            return null;
        }

        $cc = preg_replace('/[^0-9]/', '', (string) config('services.sms.default_country_code', '')) ?? '';
        if (str_starts_with($digits, '00')) {
            $candidate = '+'.substr($digits, 2);
        } elseif ($cc !== '' && str_starts_with($digits, '0')) {
            $candidate = '+'.$cc.substr($digits, 1);
        } elseif ($cc !== '' && ! str_starts_with($digits, $cc)) {
            $candidate = '+'.$cc.$digits;
        } elseif ($cc === '' && str_starts_with($digits, '0')) {
            // A local trunk number cannot be converted to E.164 safely when
            // the deployment has not declared its country code. Do not invent
            // an invalid international number such as +080… .
            return null;
        } else {
            $candidate = '+'.$digits;
        }

        return strlen($candidate) >= 8 && strlen($candidate) <= 16
            ? $candidate
            : null;
    }

    /** Masks a number for UI echo: +2348012345678 -> +234•••••5678 */
    public function mask(?string $raw): string
    {
        $number = $this->normalize($raw) ?? (string) $raw;
        if (strlen($number) <= 6) {
            return str_repeat('•', max(0, strlen($number)));
        }

        return substr($number, 0, 4).str_repeat('•', max(1, strlen($number) - 8)).substr($number, -4);
    }

    private function twilioConfigured(): bool
    {
        return (string) config('services.sms.twilio.sid') !== ''
            && (string) config('services.sms.twilio.token') !== ''
            && (string) config('services.sms.twilio.from') !== '';
    }

    private function sendViaTwilio(string $to, string $message): bool
    {
        $sid = (string) config('services.sms.twilio.sid');

        try {
            $response = Http::asForm()
                ->withBasicAuth($sid, (string) config('services.sms.twilio.token'))
                ->timeout(15)
                ->post("https://api.twilio.com/2010-04-01/Accounts/{$sid}/Messages.json", [
                    'To' => $to,
                    'From' => (string) config('services.sms.twilio.from'),
                    'Body' => $message,
                ]);

            if ($response->successful()) {
                return true;
            }

            Log::warning('Twilio SMS rejected', [
                'status' => $response->status(),
                'body' => $response->json('message') ?? $response->body(),
            ]);
        } catch (\Throwable $e) {
            report($e);
        }

        return false;
    }
}
