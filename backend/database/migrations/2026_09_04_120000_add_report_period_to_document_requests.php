<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a patient say which period a report should cover.
 *
 * The request form asked one date question — "needed by" — which is a deadline,
 * not a scope. For a referral letter that is the right question. For a report it
 * is the wrong one entirely: a report is *of* something, and the thing it is of
 * is a stretch of time. A patient asking for a vitals report for their August
 * consultation had no way to say August, so the clinician either guessed or had
 * to message them back to ask.
 *
 * Kept alongside `needed_by` rather than replacing it. They answer different
 * questions and a request can legitimately carry both — "cover August, and I
 * need it before the 14th" — and `needed_by` is what the overdue tracking the
 * patient already relies on is computed from.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('document_requests', function (Blueprint $table) {
            $table->date('period_from')->nullable()->after('needed_by');
            $table->date('period_to')->nullable()->after('period_from');
        });
    }

    public function down(): void
    {
        Schema::table('document_requests', function (Blueprint $table) {
            $table->dropColumn(['period_from', 'period_to']);
        });
    }
};
