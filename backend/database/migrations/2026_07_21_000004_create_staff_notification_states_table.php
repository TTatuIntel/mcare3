<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Per-user read/resolve state for CLIENT-COMPUTED staff notifications
 * (doctor/admin/assistant inbox items derived from alerts, SOS, requests,
 * appointments). These have no backing notification row, so their
 * read/resolve state is stored here keyed by the synthetic notification key
 * (e.g. `staff_alert_42`). This keeps "mark read" separate from the clinical
 * "acknowledge" action and lets read-state survive polls + follow the user
 * across devices.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_notification_states', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('notification_key');
            $table->timestamp('read_at')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'notification_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_notification_states');
    }
};
