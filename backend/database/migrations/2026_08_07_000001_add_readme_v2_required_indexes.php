<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * README v2 §5.4 — dedicated required-indexes migration.
 *
 * Kept in its own migration (rather than bolted onto unrelated schema
 * changes) so DBAs can audit index adds in isolation.
 *
 * Index names are explicit so `dropIndex` can find them regardless of
 * MySQL's auto-generated naming.
 */
return new class extends Migration
{
    public function up(): void
    {
        // vital_readings — patient trend history and admin analytics.
        // Existing (user_id, vital_key, recorded_at) doesn't cover queries
        // that filter user_id only or vital_key only.
        Schema::table('vital_readings', function (Blueprint $table) {
            $table->index(['user_id', 'recorded_at'], 'vr_user_recorded_idx');
            $table->index(['vital_key', 'recorded_at'], 'vr_vitalkey_recorded_idx');
        });

        // app_notifications — inbox pagination + unread badge count.
        // Existing (user_id, created_at) and (user_id, read) don't serve
        // the "unread ordered by newest" query in one seek.
        Schema::table('app_notifications', function (Blueprint $table) {
            $table->index(['user_id', 'read', 'created_at'], 'notif_user_read_created_idx');
        });

        // external_access_tokens — active-link list per patient (max 5).
        Schema::table('external_access_tokens', function (Blueprint $table) {
            $table->index(['patient_user_id', 'revoked_at'], 'eat_patient_revoked_idx');
        });

        // sos_events — live SOS hub queries filter by status first.
        Schema::table('sos_events', function (Blueprint $table) {
            $table->index(['status', 'triggered_at'], 'sos_status_triggered_idx');
        });
    }

    public function down(): void
    {
        Schema::table('sos_events', function (Blueprint $table) {
            $table->dropIndex('sos_status_triggered_idx');
        });

        Schema::table('external_access_tokens', function (Blueprint $table) {
            $table->dropIndex('eat_patient_revoked_idx');
        });

        Schema::table('app_notifications', function (Blueprint $table) {
            $table->dropIndex('notif_user_read_created_idx');
        });

        Schema::table('vital_readings', function (Blueprint $table) {
            $table->dropIndex('vr_vitalkey_recorded_idx');
            $table->dropIndex('vr_user_recorded_idx');
        });
    }
};
