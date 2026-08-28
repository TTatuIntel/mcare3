<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How an emergency ended, not just that it did.
 *
 * "resolved" alone tells a reviewer nothing: a patient reached and safe, a
 * patient transported by ambulance, and a patient nobody could reach are
 * three very different endings that were all recorded identically. The
 * outcome is now named, with room for a responder to describe one the list
 * does not cover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sos_events', function (Blueprint $table) {
            $table->string('resolution', 40)->nullable()->after('status');
            $table->string('resolution_note', 400)->nullable()->after('resolution');
        });
    }

    public function down(): void
    {
        Schema::table('sos_events', function (Blueprint $table) {
            $table->dropColumn(['resolution', 'resolution_note']);
        });
    }
};
