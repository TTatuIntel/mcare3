<?php

namespace App\Services;

use App\Mail\EmailVerificationMail;
use App\Models\EmailVerificationCode;
use App\Models\User;
use App\Support\MailDispatcher;
use App\Support\SmsSender;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Proving an address belongs to the person who typed it.
 *
 * One issue, two ways to finish it, delivered over every channel the account
 * has. A link finishes it for the reader whose mail and app are on the same
 * device; a code finishes it for the one reading mail on a desktop with the
 * app on a handset; the SMS carries the same code for the one whose mail is
 * slow or filtered. Whichever they use retires the other, because they are
 * one act of proof, not three.
 *
 * The service always reports which channels actually accepted the message.
 * The old flow answered "a code was sent" whether or not anything left the
 * server, so a patient sat at an empty inbox with nothing to tell them that
 * the send itself had failed — and no support agent could tell either.
 */
class AccountVerificationService
{
    /** Long enough to walk to a desktop, short enough to be worthless if leaked. */
    public const CODE_TTL_MINUTES = 15;

    /** What the UI counts down before offering resend again. */
    public const RESEND_COOLDOWN_SECONDS = 60;

    /** Wrong guesses before the code is burned and a new one is required. */
    public const MAX_ATTEMPTS = 5;

    public function __construct(private readonly SmsSender $sms) {}

    /**
     * Mint a fresh verification and deliver it everywhere it can go.
     *
     * @param  list<string>|null  $only  restrict delivery to these channels
     *                                   ('email', 'sms'); null means every
     *                                   channel the account supports.
     * @return array<string, mixed> the dispatch, shaped for the API payload
     */
    public function issue(User $user, ?array $only = null): array
    {
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $linkToken = Str::random(48);

        // Previous codes die the moment a new one is minted. Two live codes
        // means a stale email still works, which is exactly the window an
        // attacker who saw an earlier message would want.
        EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'email_verify')
            ->whereNull('used_at')
            ->update(['used_at' => now()]);

        $record = EmailVerificationCode::create([
            'user_id' => $user->id,
            'code' => Hash::make($code),
            'link_token' => hash('sha256', $linkToken),
            'purpose' => 'email_verify',
            'expires_at' => now()->addMinutes(self::CODE_TTL_MINUTES),
            'attempts' => 0,
        ]);

        $wants = fn (string $channel) => $only === null || in_array($channel, $only, true);
        $delivered = [];

        if ($wants('email') && filled($user->email)) {
            $sent = MailDispatcher::send(
                $user->email,
                new EmailVerificationMail(
                    $user,
                    $code,
                    $this->linkUrl($linkToken),
                    self::CODE_TTL_MINUTES,
                ),
                ['purpose' => 'email_verify'],
            );
            if ($sent) {
                $delivered[] = 'email';
            }
        }

        if ($wants('sms') && filled($user->phone)) {
            $sent = $this->sms->send(
                $user->phone,
                "{$code} is your mCare verification code. It expires in "
                    .self::CODE_TTL_MINUTES.' minutes.',
            );
            if ($sent) {
                $delivered[] = 'sms';
            }
        }

        $record->update(['channels' => implode(',', $delivered) ?: null]);

        return $this->describe($user, $delivered, $record);
    }

    /**
     * Check a typed code.
     *
     * Wrong guesses are counted against the code itself, not the account: the
     * person guessing may not be the account holder, and locking the account
     * would hand any stranger a way to lock anyone out of theirs.
     */
    public function verifyCode(User $user, string $code): bool
    {
        $record = EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'email_verify')
            ->orderByDesc('created_at')
            ->first();

        if (! $record || ! $record->isValid()) {
            return false;
        }

        // Older rows were stored in plain text; both forms have to keep
        // working until every one of them has expired out of the table.
        $matches = str_starts_with((string) $record->code, '$2')
            ? Hash::check($code, $record->code)
            : hash_equals((string) $record->code, $code);

        if (! $matches) {
            $record->increment('attempts');
            if ((int) $record->fresh()->attempts >= self::MAX_ATTEMPTS) {
                $record->update(['used_at' => now()]);
            }

            return false;
        }

        $this->markVerified($user, $record);

        return true;
    }

    /**
     * Consume an emailed link.
     *
     * Returns the owner on success so the caller can say who was verified,
     * and null for anything else — expired, already used, or invented. The
     * reasons are deliberately not distinguished to the caller's caller: a
     * page that says "already used" tells a stranger holding a stale link
     * that the address is real.
     */
    public function consumeLink(string $token): ?User
    {
        $record = EmailVerificationCode::query()
            ->where('link_token', hash('sha256', $token))
            ->where('purpose', 'email_verify')
            ->first();

        if (! $record || ! $record->isValid()) {
            return null;
        }

        $user = $record->user;
        if (! $user) {
            return null;
        }

        $this->markVerified($user, $record);

        return $user;
    }

    /**
     * What the client needs to render the waiting state without guessing.
     *
     * The old screen hard-coded a 30-second countdown that had nothing to do
     * with the server, so it offered a resend the API would refuse and hid one
     * the API would have allowed.
     */
    public function status(User $user): array
    {
        $record = EmailVerificationCode::query()
            ->where('user_id', $user->id)
            ->where('purpose', 'email_verify')
            ->orderByDesc('created_at')
            ->first();

        $channels = $record && filled($record->channels)
            ? explode(',', (string) $record->channels)
            : [];

        return $this->describe($user, $channels, $record);
    }

    /** Seconds until a resend is worth offering. */
    public function retryAfterSeconds(?EmailVerificationCode $record): int
    {
        if (! $record || ! $record->created_at) {
            return 0;
        }

        $elapsed = $record->created_at->diffInSeconds(now());

        return (int) max(0, self::RESEND_COOLDOWN_SECONDS - $elapsed);
    }

    /** The address a code went to, safe to echo back on screen. */
    public function maskEmail(?string $email): ?string
    {
        if (! filled($email)) {
            return null;
        }

        $at = strpos($email, '@');
        if ($at === false || $at === 0) {
            return str_repeat('•', strlen($email));
        }

        $name = substr($email, 0, $at);
        $domain = substr($email, $at);

        return strlen($name) <= 2
            ? str_repeat('•', strlen($name)).$domain
            : $name[0].str_repeat('•', max(1, strlen($name) - 2)).$name[-1].$domain;
    }

    /** Where an emailed link points. Hits the API so it works from any inbox. */
    private function linkUrl(string $token): string
    {
        return rtrim((string) config('app.url'), '/')
            .'/api/v1/auth/verify-email/'.$token;
    }

    private function markVerified(User $user, EmailVerificationCode $record): void
    {
        $record->update(['used_at' => now()]);

        if ($user->email_verified_at === null) {
            $user->forceFill(['email_verified_at' => now()])->save();
        }
    }

    /**
     * @param  list<string>  $channels
     * @return array<string, mixed>
     */
    private function describe(
        User $user,
        array $channels,
        ?EmailVerificationCode $record,
    ): array {
        return [
            'delivered' => $channels !== [],
            'channels' => array_values($channels),
            'email' => $this->maskEmail($user->email),
            'phone' => filled($user->phone) ? $this->sms->mask($user->phone) : null,
            // Offered so the client can show "send it by SMS instead" only
            // when there is actually a number to send it to.
            'sms_available' => filled($user->phone),
            'expires_at' => $record?->expires_at?->toIso8601String(),
            'retry_after' => $this->retryAfterSeconds($record),
        ];
    }
}
