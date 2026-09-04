<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a published clinical report reach the patient as a document.
 *
 * A clinical report was the one report type that told the patient about itself
 * and then had nothing for them to open. Publishing wrote a notification whose
 * `action_route` is `/patient/documents` — so the patient tapped "New clinical
 * report", landed on their documents, and found an empty list. The report
 * existed only as a row the doctor could see.
 *
 * `clinical_report_id` is the same device `issued_report_id` already uses for
 * record disclosures: it links the patient's copy back to what produced it, and
 * being unique it makes a duplicate copy impossible rather than merely
 * unlikely — republishing, or two calls racing, cannot leave the patient
 * holding two versions of one report with no way to tell which is current.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->foreignId('clinical_report_id')
                ->nullable()
                ->after('issued_report_id')
                ->constrained('clinical_reports')
                ->nullOnDelete();

            $table->unique('clinical_report_id', 'medical_documents_clinical_report_unique');
        });
    }

    /**
     * The foreign key has to be lifted first: MySQL drops the index it created
     * for the column once the unique one can serve the same constraint, so by
     * now the unique index is what backs the foreign key and dropping it
     * directly is refused with "needed in a foreign key constraint".
     */
    public function down(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropForeign(['clinical_report_id']);
        });

        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropUnique('medical_documents_clinical_report_unique');
            $table->dropColumn('clinical_report_id');
        });
    }
};
