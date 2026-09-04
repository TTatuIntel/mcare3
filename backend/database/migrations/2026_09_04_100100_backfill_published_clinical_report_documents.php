<?php

use App\Models\ClinicalReport;
use App\Models\MedicalDocument;
use App\Support\ClinicalReportPublisher;
use Illuminate\Database\Migrations\Migration;

/**
 * Gives already-published clinical reports the document they never got.
 *
 * Every report published before delivery existed left a patient holding a
 * notification — "New clinical report" — pointing at a documents screen with
 * nothing on it. Fixing the publish path only helps reports written from now
 * on; the ones already sent stay broken forever unless they are filed here.
 *
 * Deliberately silent. These patients were notified at the time, and a second
 * alert would claim something new had happened when nothing did — the document
 * simply appears under the notification they already have.
 */
return new class extends Migration
{
    public function up(): void
    {
        ClinicalReport::query()
            ->where('published', true)
            ->whereNotExists(function ($query) {
                $query->selectRaw(1)
                    ->from('medical_documents')
                    ->whereColumn('medical_documents.clinical_report_id', 'clinical_reports.id');
            })
            ->with(['patient', 'author'])
            ->orderBy('id')
            ->chunkById(100, function ($reports) {
                foreach ($reports as $report) {
                    $author = $report->author;
                    $label = $author === null
                        ? 'Your care team'
                        : ($author->role === 'doctor'
                            ? 'Dr. '.$author->fullName()
                            : $author->fullName());

                    ClinicalReportPublisher::publish($report, $label, announce: false);
                }
            });
    }

    /**
     * Removes only what this migration could have created: the filed copies of
     * clinical reports. A document with no `clinical_report_id` was never ours
     * to delete, and the column itself goes in the migration that added it.
     */
    public function down(): void
    {
        MedicalDocument::whereNotNull('clinical_report_id')
            ->get()
            ->each(function (MedicalDocument $document) {
                \App\Support\MedicalDocumentFiles::deleteStoredFile($document->storage_path);
                $document->delete();
            });
    }
};
