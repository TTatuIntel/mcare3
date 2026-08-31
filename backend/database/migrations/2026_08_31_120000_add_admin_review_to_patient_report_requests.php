<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets an admin send a signed report back to the doctor instead of only being
 * able to issue it or destroy it.
 *
 * The workflow had exactly two exits once a doctor signed: issue the report, or
 * revoke the whole request — which throws away the patient's consent along with
 * it and forces the admin to start again, re-asking a patient who has already
 * said yes. The common real case is neither: the report is nearly right and
 * needs a correction from the doctor who signed it. These columns record that
 * return trip so the doctor can see what was wrong, and so the request's
 * history shows a report that came back rather than one that was simply slow.
 *
 * Sending back clears `signed_at` — the signature applied to content that is
 * about to change, and must be given again against the corrected document.
 * All columns are nullable; existing rows read as "never returned".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patient_report_requests', function (Blueprint $table) {
            $table->timestamp('returned_at')->nullable()->after('signature_note');

            $table->foreignId('returned_by_user_id')
                ->nullable()
                ->after('returned_at')
                ->constrained('users')
                ->nullOnDelete();

            // What the admin asked the doctor to change.
            $table->string('return_note', 280)->nullable()->after('returned_by_user_id');

            // How many round trips this report has taken. Surfaced to both
            // sides: a report on its third return is a conversation that has
            // stopped working, and staff should be able to see that.
            $table->unsignedTinyInteger('return_count')->default(0)->after('return_note');
        });
    }

    public function down(): void
    {
        Schema::table('patient_report_requests', function (Blueprint $table) {
            $table->dropConstrainedForeignId('returned_by_user_id');
            $table->dropColumn(['returned_at', 'return_note', 'return_count']);
        });
    }
};
