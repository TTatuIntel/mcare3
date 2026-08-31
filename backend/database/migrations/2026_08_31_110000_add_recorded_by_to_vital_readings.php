<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Records who entered a reading when it was not the patient.
 *
 * Staff can now log a vital on a patient's behalf — the nurse who took the
 * blood pressure at the desk, the assistant reading numbers back over the
 * phone. A clinician looking at that row later has to be able to tell whether
 * the patient measured it themselves or someone else typed it in, because the
 * two carry different confidence and the row may be the basis of an alert.
 *
 * Nullable and unread by the existing patient path: a null means the patient
 * entered it themselves, which is what every row before this migration was.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vital_readings', function (Blueprint $table) {
            $table->foreignId('recorded_by_user_id')
                ->nullable()
                ->after('note')
                ->constrained('users')
                ->nullOnDelete();

            // Denormalised so the row still says who took it after the staff
            // account is deactivated or renamed.
            $table->string('recorded_by_label')->nullable()->after('recorded_by_user_id');
        });
    }

    public function down(): void
    {
        Schema::table('vital_readings', function (Blueprint $table) {
            $table->dropConstrainedForeignId('recorded_by_user_id');
            $table->dropColumn('recorded_by_label');
        });
    }
};
