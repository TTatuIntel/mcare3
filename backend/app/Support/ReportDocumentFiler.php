<?php

namespace App\Support;

use App\Models\MedicalDocument;
use Illuminate\Database\UniqueConstraintViolationException;

/**
 * Puts a report the care team produced into the patient's own documents.
 *
 * Three different things in this system are called a report, they are produced
 * by three unrelated flows, and every one of them ends at the same place: a
 * file the patient can open from the documents screen.
 *
 *   - a vital report, from a request the patient raised
 *   - a record disclosure, signed by a doctor and issued by an admin
 *   - a clinical report or chart note, written and published by a clinician
 *
 * The first two each grew their own copy of "render it, store it, create the
 * row, tell the patient", and the copies had already drifted — one filed under
 * a report category and the other under "other". The third never got a copy at
 * all, which is why publishing a clinical report sent the patient a
 * notification pointing at a documents screen that had nothing on it.
 *
 * One implementation, so a fourth kind of report cannot be added without the
 * patient being able to open it.
 */
final class ReportDocumentFiler
{
    /**
     * Files [$html] as the patient's copy of a report.
     *
     * Idempotent through [$linkColumn]: that column is unique, so a republish,
     * a retry after a partial failure, or two calls racing all end with exactly
     * one document. The loser of a race cleans up the file it wrote rather than
     * leaving it orphaned on disk.
     *
     * Never throws. By the time this runs the report itself has been published
     * and audited; failing here would report a completed act as failed and
     * invite staff to do it twice.
     */
    public static function file(
        int $ownerUserId,
        string $title,
        string $html,
        string $category,
        string $uploadedBy,
        ?string $description = null,
        ?string $linkColumn = null,
        ?int $linkId = null,
    ): ?MedicalDocument {
        try {
            if ($linkColumn !== null && $linkId !== null) {
                $existing = MedicalDocument::where($linkColumn, $linkId)->first();
                if ($existing !== null) {
                    return $existing;
                }
            }

            $stored = MedicalDocumentFiles::storeGeneratedFile(
                $ownerUserId,
                $title,
                $html,
            );

            try {
                return MedicalDocument::create([
                    'user_id' => $ownerUserId,
                    'title' => $title,
                    'category' => $category,
                    'file_type' => 'other',
                    // Rendered HTML, recorded as such. Stored with no type it
                    // was served as octet-stream named ".bin", which no browser
                    // renders and no phone will open.
                    'mime_type' => $stored['mime'],
                    'original_filename' => $stored['original_name'],
                    'storage_path' => $stored['path'],
                    'size_bytes' => $stored['size'],
                    'description' => $description,
                    'uploaded_by' => $uploadedBy,
                    'uploaded_at' => now(),
                    // An issued report: part of the record, and not deletable
                    // by the patient or by the clinician who wrote it.
                    'source' => MedicalDocument::SOURCE_REPORT,
                ] + ($linkColumn !== null && $linkId !== null ? [$linkColumn => $linkId] : []));
            } catch (UniqueConstraintViolationException) {
                // Another call filed it first. The patient has their copy,
                // which is the whole objective — drop the file this call wrote
                // rather than leave it orphaned on disk.
                MedicalDocumentFiles::deleteStoredFile($stored['path']);

                return $linkColumn !== null && $linkId !== null
                    ? MedicalDocument::where($linkColumn, $linkId)->first()
                    : null;
            }
        } catch (\Throwable $e) {
            report($e);

            return null;
        }
    }

    /**
     * Rewrites the file behind an already-filed report.
     *
     * A clinical report stays editable after publication, and a patient holding
     * last week's wording of a report their doctor has since corrected is worse
     * than one holding none. The document row — and so the patient's link to it
     * — survives; only the content and the size change.
     *
     * Deliberately not offered for issued record disclosures: those are frozen
     * from a snapshot on purpose, because they are evidence of exactly what was
     * disclosed to a third party.
     */
    public static function refile(
        MedicalDocument $document,
        string $title,
        string $html,
    ): ?MedicalDocument {
        try {
            $stored = MedicalDocumentFiles::storeGeneratedFile(
                (int) $document->user_id,
                $title,
                $html,
            );

            $previous = $document->storage_path;

            $document->forceFill([
                'title' => $title,
                'storage_path' => $stored['path'],
                'size_bytes' => $stored['size'],
                'mime_type' => $stored['mime'],
                'original_filename' => $stored['original_name'],
                'uploaded_at' => now(),
            ])->save();

            // Only once the row points at the new file, so a failure above
            // leaves the patient with the old copy rather than none.
            MedicalDocumentFiles::deleteStoredFile($previous);

            return $document;
        } catch (\Throwable $e) {
            report($e);

            return null;
        }
    }
}
