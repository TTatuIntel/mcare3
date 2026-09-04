<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A vital report is issued the moment a clinician fulfils the request, and
     * "prepared by" was the only trace of who stood behind it. That is an
     * author line, not a signature: it says who typed the note, not who
     * attests to the findings the patient is about to be handed.
     *
     * The signature is recorded on the request itself so it survives
     * independently of the rendered file, and so the patient can be shown who
     * signed and when without re-reading the document.
     */
    public function up(): void
    {
        Schema::table('vital_report_requests', function (Blueprint $table) {
            $table->foreignId('signed_by_user_id')->nullable()->after('response_note')
                ->constrained('users')->nullOnDelete();
            $table->string('signed_by')->nullable()->after('signed_by_user_id');
            $table->string('signed_by_role', 32)->nullable()->after('signed_by');
            $table->timestamp('signed_at')->nullable()->after('signed_by_role');
        });
    }

    public function down(): void
    {
        Schema::table('vital_report_requests', function (Blueprint $table) {
            $table->dropConstrainedForeignId('signed_by_user_id');
            $table->dropColumn(['signed_by', 'signed_by_role', 'signed_at']);
        });
    }
};
