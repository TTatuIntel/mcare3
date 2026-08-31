<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Records where a document came from, so the record can be protected from
 * the people who file into it.
 *
 * Until now every row looked the same: a discharge summary a consultant filed
 * and a photo of a pill bottle the patient uploaded differed only by a free-text
 * `uploaded_by` label, which is far too soft a thing to hang a delete rule on.
 * `source` makes the distinction explicit so a clinical document — and above
 * all an issued report, which is a disclosure someone consented to — cannot be
 * quietly removed by staff or by the patient.
 *
 * `issued_report_id` links the copy filed into the patient's documents back to
 * the report request it was generated from, so re-issuing cannot silently
 * produce a second copy and the audit trail joins up in both directions.
 *
 * Both columns are nullable and unread by existing code paths: rows written
 * before this migration keep working and are treated as patient uploads, which
 * is what they were.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            // patient | clinician | report — null means legacy patient upload.
            $table->string('source', 16)->nullable()->after('uploaded_by');

            $table->foreignId('issued_report_id')
                ->nullable()
                ->after('source')
                ->constrained('patient_report_requests')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropConstrainedForeignId('issued_report_id');
            $table->dropColumn('source');
        });
    }
};
