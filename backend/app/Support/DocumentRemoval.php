<?php

namespace App\Support;

use App\Models\AppNotification;
use App\Models\MedicalDocument;
use App\Models\User;
use App\Services\AuditService;

/**
 * The one authorised route out of a patient's document record.
 *
 * Nothing filed into a patient's record can be deleted by the people who file
 * into it — see {@see MedicalDocument::isDeletableBy()}. That rule is right and
 * it is also incomplete: it left a document filed against the wrong patient
 * permanently attached to them, with no way for the person it libels to get it
 * taken out. This is the exception, and the patient's own request is the thing
 * that opens it. Staff cannot start it, only answer it.
 *
 * Both staff-side answers live here rather than in each controller because
 * doctors and admins reach the same document by different routes and must not
 * be able to answer the same request in two different ways.
 */
final class DocumentRemoval
{
    /**
     * The patient asks for a document to be taken out.
     *
     * Re-asking after a refusal is allowed and clears the refusal: staff saying
     * no once should not silence a patient who has since found the evidence.
     */
    public static function request(MedicalDocument $document, string $reason): void
    {
        $document->update([
            'removal_requested_at' => now(),
            'removal_reason' => $reason,
            'removal_declined_at' => null,
            'removal_declined_reason' => null,
        ]);

        self::notifyCareTeam($document, $reason);
    }

    /** The patient changes their mind before staff have answered. */
    public static function withdraw(MedicalDocument $document): void
    {
        $document->update([
            'removal_requested_at' => null,
            'removal_reason' => null,
        ]);
    }

    /**
     * Staff honour the request: the file and the row both go.
     *
     * This is a real delete, which everywhere else in the record is refused.
     * What makes it safe is that it is unreachable without a standing patient
     * request, and that the audit entry outlives the row — it keeps the title,
     * who filed it, why the patient wanted it gone and who agreed, so removing
     * the document does not remove the fact that it existed.
     */
    public static function honour(
        AuditService $audit,
        User $actor,
        MedicalDocument $document,
        ?string $note,
    ): void {
        $snapshot = [
            'document_id' => $document->id,
            'patient_user_id' => $document->user_id,
            'target_user_id' => $document->user_id,
            'title' => $document->title,
            'category' => $document->category,
            'uploaded_by' => $document->uploaded_by,
            'uploaded_at' => $document->uploaded_at?->toIso8601String(),
            'patient_reason' => $document->removal_reason,
            'requested_at' => $document->removal_requested_at?->toIso8601String(),
            'staff_note' => $note,
        ];

        $title = $document->title;
        $ownerId = $document->user_id;

        MedicalDocumentFiles::deleteStoredFile($document->storage_path);
        $document->delete();

        $audit->record(
            $actor,
            'patient.document_removed',
            $title,
            'security',
            $snapshot,
        );

        self::tellPatient(
            $ownerId,
            'Document removed from your records',
            '"'.$title.'" was taken out of your records as you asked.'
                .($note ? ' '.$note : ''),
        );
    }

    /**
     * Staff decline: the document stays and the patient is told why.
     *
     * A refusal is an answer, not a dead end — the request is cleared so the
     * queue does not carry it forever, and the reason is kept on the document
     * so the patient reads it next to the thing they asked about.
     */
    public static function decline(
        AuditService $audit,
        User $actor,
        MedicalDocument $document,
        string $reason,
    ): void {
        $document->update([
            'removal_requested_at' => null,
            'removal_declined_at' => now(),
            'removal_declined_reason' => $reason,
        ]);

        $audit->record(
            $actor,
            'patient.document_removal_declined',
            $document->title,
            'security',
            [
                'document_id' => $document->id,
                'patient_user_id' => $document->user_id,
                'target_user_id' => $document->user_id,
                'patient_reason' => $document->removal_reason,
                'reason' => $reason,
            ],
        );

        self::tellPatient(
            $document->user_id,
            'Removal request declined',
            '"'.$document->title.'" stays in your records. Reason: '.$reason,
        );
    }

    /**
     * Tells whoever filed the document that the patient wants it out.
     *
     * Addressed to the uploader by id where we have one; a document filed by
     * admin staff has no single owner, so it surfaces in the admin queue by the
     * pending flag alone rather than pinging an arbitrary person.
     */
    private static function notifyCareTeam(MedicalDocument $document, string $reason): void
    {
        try {
            $doctorId = $document->shared_with_doctor_id;
            if (! $doctorId) {
                return;
            }

            AppNotification::create([
                'user_id' => $doctorId,
                'kind' => 'document',
                'title' => 'Patient asked for a document to be removed',
                'body' => ($document->user?->fullName() ?? 'A patient')
                    .' asked for "'.$document->title.'" to be taken out of '
                    .'their records. Reason: '.$reason,
                'action_route' => '/doctor/patients',
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Never throws. The removal itself has already happened and been audited;
     * failing here would report a completed action as failed and invite staff
     * to do it twice.
     */
    private static function tellPatient(int $userId, string $title, string $body): void
    {
        try {
            AppNotification::create([
                'user_id' => $userId,
                'kind' => 'document',
                'title' => $title,
                'body' => $body,
                'action_route' => '/patient/documents',
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
