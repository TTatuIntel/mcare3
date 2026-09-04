<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Makes documents already in the record behave like ones filed from now on.
 *
 * Two things were only ever written at creation time, so every existing row
 * carries the old behaviour permanently unless it is filled in here:
 *
 *  - `mime_type`, without which a stored file is served as
 *    `application/octet-stream`. That is survivable for a PDF, whose extension
 *    still tells the browser what it is, and fatal for the HTML reports the
 *    server renders itself — they were handed over named `.bin`. Patients who
 *    were issued a report before today would keep an unopenable copy forever.
 *
 *  - the `report` category, which did not exist when those reports were filed,
 *    so the patient's copy of a disclosure went in as "other" and does not
 *    appear under Reports where they look for it.
 *
 * Derived from the stored file path, which is the one piece of evidence about
 * these rows that is not a guess.
 */
return new class extends Migration
{
    /** Extension to content type, for rows written before the column existed. */
    private const MIMES = [
        'pdf' => 'application/pdf',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        'bmp' => 'image/bmp',
        'tif' => 'image/tiff',
        'tiff' => 'image/tiff',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'odt' => 'application/vnd.oasis.opendocument.text',
        'rtf' => 'application/rtf',
        'txt' => 'text/plain',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'csv' => 'text/csv',
        'html' => 'text/html',
        'htm' => 'text/html',
    ];

    public function up(): void
    {
        DB::table('medical_documents')
            ->whereNull('mime_type')
            ->whereNotNull('storage_path')
            ->orderBy('id')
            ->chunkById(500, function ($rows) {
                foreach ($rows as $row) {
                    $extension = strtolower(pathinfo((string) $row->storage_path, PATHINFO_EXTENSION));
                    $mime = self::MIMES[$extension] ?? null;
                    if ($mime === null) {
                        continue;
                    }

                    DB::table('medical_documents')
                        ->where('id', $row->id)
                        ->update(['mime_type' => $mime]);
                }
            });

        // Issued clinical reports that predate the category. Narrowed by
        // `issued_report_id` rather than by source alone so a vital report —
        // which has always had its own category — is left where it is.
        DB::table('medical_documents')
            ->whereNotNull('issued_report_id')
            ->where('category', 'other')
            ->update(['category' => 'report']);
    }

    /**
     * Irreversible by design. Blanking these would put back a state whose only
     * property was being wrong, and the old category is not recoverable — the
     * rows this touched are indistinguishable from ones legitimately filed as
     * "other".
     */
    public function down(): void
    {
        // No-op.
    }
};
