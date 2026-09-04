<?php

use App\Models\User;
use App\Models\VitalReportRequest;
use App\Services\VitalReportIssuer;
use Illuminate\Database\Migrations\Migration;

/**
 * Gives fulfilled vital report requests the report they promised.
 *
 * A request could reach `fulfilled` with `document_id` null — seeded demo rows
 * did exactly that, and so did any fulfilment whose rendering failed. The
 * patient's screen then showed the request as answered and offered nothing to
 * open: the report existed as a status and a note, not as a document.
 *
 * Rendered from the readings inside the window the request asked for, which is
 * what the fulfil path does, so a backfilled report and a freshly issued one
 * are the same document.
 *
 * Silent by design: these patients were told at the time their report was
 * ready, and a second alert would claim something new had happened.
 */
return new class extends Migration
{
    public function up(): void
    {
        $issuer = app(VitalReportIssuer::class);

        VitalReportRequest::query()
            ->where('status', VitalReportRequest::FULFILLED)
            ->whereNull('document_id')
            ->orderBy('id')
            ->chunkById(50, function ($requests) use ($issuer) {
                foreach ($requests as $request) {
                    $author = $request->signed_by_user_id
                        ? User::find($request->signed_by_user_id)
                        : null;

                    $label = $request->signed_by
                        ?? $request->responded_by
                        ?? 'Your care team';

                    $document = $issuer->issue(
                        $request,
                        // The issuer only reads the author for its own audit
                        // trail; a seeded row may name nobody, and the label
                        // above is what the patient actually reads.
                        $author ?? new User(),
                        $label,
                        $request->response_note,
                    );

                    if ($document !== null) {
                        $request->forceFill(['document_id' => $document->id])->save();
                    }
                }
            });
    }

    /**
     * Irreversible on purpose. The documents this filed are indistinguishable
     * from ones issued normally, and deleting a patient's report to undo a
     * data migration is worse than leaving it.
     */
    public function down(): void
    {
        // No-op.
    }
};
