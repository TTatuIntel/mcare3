<?php

use App\Models\MedicalDocument;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Remembers what a stored file actually *is*, and makes a duplicated report
 * copy impossible rather than merely unlikely.
 *
 * The type of every document was being re-derived from `file_type`, a
 * four-value enum shared with the Flutter app: pdf, image, doc, other. That is
 * enough to pick an icon and nothing like enough to hand a file to a browser
 * or a share sheet. An issued report — HTML the server renders itself — is
 * `other`, so it was handed over as `application/octet-stream` named `.bin`,
 * which no viewer on any platform will open. The patient was told their report
 * was ready and then given a file their phone could not read.
 *
 * `mime_type` and `original_filename` record the truth once, at the point where
 * it is still known, so open and download stop guessing.
 *
 * The unique index on `issued_report_id` closes the other half. Filing the
 * patient's copy of a report checked for an existing row first, which is a
 * read-then-write with a gap in the middle: two issue calls racing, or a retry
 * after a partial failure, could both pass the check. A patient holding two
 * copies of one disclosure cannot tell which is the real one.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            // The real content type of the stored file, captured at upload or
            // generation. Null on legacy rows, which fall back to the old
            // guess-from-file_type behaviour.
            $table->string('mime_type', 191)->nullable()->after('file_type');

            // What the file was called when it arrived. A patient who uploads
            // "MRI-2026-03-11.pdf" should get that name back on download, not
            // a slug of the title with a guessed extension.
            $table->string('original_filename', 255)->nullable()->after('mime_type');
        });

        // Collapse any duplicate report copies before the index can refuse
        // them. Keeping the earliest is the right choice: it is the one the
        // patient was notified about and the one any link points at.
        $duplicated = DB::table('medical_documents')
            ->select('issued_report_id')
            ->whereNotNull('issued_report_id')
            ->groupBy('issued_report_id')
            ->havingRaw('COUNT(*) > 1')
            ->pluck('issued_report_id');

        foreach ($duplicated as $reportId) {
            $keep = DB::table('medical_documents')
                ->where('issued_report_id', $reportId)
                ->orderBy('id')
                ->value('id');

            DB::table('medical_documents')
                ->where('issued_report_id', $reportId)
                ->where('id', '!=', $keep)
                ->update(['issued_report_id' => null]);
        }

        Schema::table('medical_documents', function (Blueprint $table) {
            $table->unique('issued_report_id', 'medical_documents_issued_report_unique');
        });
    }

    /**
     * The foreign key has to be lifted first.
     *
     * MySQL drops the index it created for `issued_report_id` once the unique
     * one above can serve the same constraint, so by now the unique index *is*
     * what backs the foreign key and dropping it directly is refused with
     * "needed in a foreign key constraint". The key is put back afterwards
     * exactly as the provenance migration declared it.
     */
    public function down(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropForeign(['issued_report_id']);
        });

        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropUnique('medical_documents_issued_report_unique');
            $table->dropColumn(['mime_type', 'original_filename']);
        });

        Schema::table('medical_documents', function (Blueprint $table) {
            $table->foreign('issued_report_id')
                ->references('id')
                ->on('patient_report_requests')
                ->nullOnDelete();
        });
    }
};
