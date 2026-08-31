<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Two ways out of the same verification, and a record of how it was sent.
 *
 * A six-digit code assumes the person can read the mail and type into the app
 * at the same moment. That is true on a phone and false everywhere else — a
 * patient reading mail on a clinic desktop had to copy digits across to a
 * handset, and one transposed digit sent them back to the inbox. The link is
 * for the reader whose mail and app are on the same device; the code is for
 * everyone else. Both belong to one issue, so using either finishes the job
 * and retires the other.
 *
 * `channels` records where the code actually went. Without it, "I never got
 * it" could not be answered: nothing said whether the email was accepted, the
 * SMS was accepted, or neither ever left the server.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('email_verification_codes', function (Blueprint $table) {
            // SHA-256 of the emailed token. Hashed so a leaked database row
            // cannot be replayed as a link, but unsalted-deterministic so the
            // incoming token can still be looked up in one indexed query —
            // bcrypt would force a scan of every outstanding row.
            $table->char('link_token', 64)->nullable()->unique()->after('code');
            $table->string('channels', 64)->nullable()->after('purpose');
        });
    }

    public function down(): void
    {
        Schema::table('email_verification_codes', function (Blueprint $table) {
            $table->dropUnique(['link_token']);
            $table->dropColumn(['link_token', 'channels']);
        });
    }
};
