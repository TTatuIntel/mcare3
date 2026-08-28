<?php

namespace App\Console\Commands;

use App\Models\MedicalDocument;
use App\Support\MedicalDocumentFiles;
use Illuminate\Console\Command;

class RepairMedicalDocumentFiles extends Command
{
    protected $signature = 'documents:repair-missing-files';

    protected $description = 'Attach sample files to medical documents missing storage_path or with missing files on disk';

    public function handle(): int
    {
        $repaired = 0;

        foreach (MedicalDocument::query()->orderBy('id')->cursor() as $document) {
            $missing = ! $document->storage_path;
            $orphaned = $document->storage_path && ! MedicalDocumentFiles::exists($document->storage_path);

            if (! $missing && ! $orphaned) {
                continue;
            }

            if ($orphaned) {
                MedicalDocumentFiles::deleteStoredFile($document->storage_path);
            }

            $stored = MedicalDocumentFiles::storeFixtureCopy(
                $document->user_id,
                $document->title,
                $document->file_type,
            );

            $document->storage_path = $stored['path'];
            if (! $document->size_bytes) {
                $document->size_bytes = $stored['size'];
            }
            $document->save();
            $repaired++;
            $this->line("Repaired document #{$document->id} ({$document->title})");
        }

        $this->info("Repaired {$repaired} document(s).");

        return self::SUCCESS;
    }
}
