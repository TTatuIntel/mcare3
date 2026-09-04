<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The patient's route to having a clinician-filed document taken out.
 *
 * Staff cannot delete anything in a patient's record, which is right — but it
 * left the patient with no way at all to get a document removed that should
 * never have been filed against them: a result belonging to another patient, a
 * letter with the wrong name, a scan uploaded to the wrong chart. Their only
 * option was to ask by phone and hope, with nothing recorded either way.
 *
 * These columns turn that into an auditable request. The patient asks and says
 * why; staff can then honour it — the one circumstance in which a clinician
 * document may be deleted — or decline it with a reason the patient reads. The
 * request itself is the authorisation, which is why it is stored on the
 * document rather than held in a queue somewhere the delete path cannot see.
 *
 * Issued reports are deliberately out of scope: a disclosure the patient
 * consented to is revoked, not deleted, and revoking already exists.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->timestamp('removal_requested_at')->nullable()->after('issued_report_id');
            $table->string('removal_reason', 280)->nullable()->after('removal_requested_at');

            // Set when staff say no. Cleared if the patient asks again, so a
            // stale refusal never masks a live request.
            $table->timestamp('removal_declined_at')->nullable()->after('removal_reason');
            $table->string('removal_declined_reason', 280)->nullable()->after('removal_declined_at');
        });
    }

    public function down(): void
    {
        Schema::table('medical_documents', function (Blueprint $table) {
            $table->dropColumn([
                'removal_requested_at',
                'removal_reason',
                'removal_declined_at',
                'removal_declined_reason',
            ]);
        });
    }
};
