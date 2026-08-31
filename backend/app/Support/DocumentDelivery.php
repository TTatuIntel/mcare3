<?php

namespace App\Support;

use App\Models\AppNotification;
use App\Models\MedicalDocument;

/**
 * Tells a patient that something new was filed in their record.
 *
 * A clinician uploading a discharge summary, a lab result or a signed report
 * used to be a silent write: the row appeared in the patient's documents list
 * and nothing anywhere said so. Patients only found out by opening the app and
 * scrolling, which for a result someone needs to act on is not delivery at all.
 *
 * Every path that puts a document into a patient's record — doctor, admin,
 * external reviewer, an issued report — routes through here so the patient is
 * told the same way each time, and so a new upload path cannot forget to.
 */
final class DocumentDelivery
{
    /**
     * Announces [$document] to the patient who owns it.
     *
     * Never throws: a notification is not worth failing an upload that has
     * already stored the file. A patient who missed the alert can still find
     * the document; a caller that 500s after writing leaves the clinician
     * unsure whether to upload it again.
     */
    public static function notifyOwner(MedicalDocument $document, string $actorLabel): void
    {
        try {
            AppNotification::create([
                'user_id' => $document->user_id,
                'kind' => 'document',
                'title' => 'New document from '.$actorLabel,
                'body' => $actorLabel.' added "'.$document->title.'" ('
                    .self::categoryLabel($document->category).') to your records.',
                'action_route' => '/patient/documents',
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * The category keys are camelCase enum names shared with the Flutter app;
     * a patient should not be shown "consultationNote".
     */
    private static function categoryLabel(?string $category): string
    {
        return match ($category) {
            'labResult' => 'lab result',
            'prescription' => 'prescription',
            'imaging' => 'imaging',
            'discharge' => 'discharge summary',
            'consultationNote' => 'consultation note',
            default => 'document',
        };
    }
}
