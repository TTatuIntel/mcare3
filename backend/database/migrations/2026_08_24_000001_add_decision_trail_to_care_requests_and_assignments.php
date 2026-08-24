<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Care requests and care assignments are triaged from a single admin screen.
 * Both sides now carry the decision trail the screen shows back to staff and
 * to the patient: who decided, when, which provider was actually assigned,
 * and the free-text reason attached to an approval / re-assignment / decline.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('care_requests', function (Blueprint $table) {
            // Provider actually assigned — differs from provider_id whenever an
            // admin routes the patient to a more suitable doctor.
            $table->foreignId('assigned_provider_id')
                ->nullable()
                ->after('provider_specialty')
                ->constrained('care_providers')
                ->nullOnDelete();
            $table->string('assignment_role', 32)->nullable()->after('assigned_provider_id');
            $table->string('decision_note', 280)->nullable()->after('reason');
            $table->foreignId('decided_by')
                ->nullable()
                ->after('status')
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('decided_at')->nullable()->after('decided_by');
            $table->index(['status', 'created_at']);
        });

        Schema::table('care_assignments', function (Blueprint $table) {
            $table->string('assigned_reason', 280)->nullable()->after('role');
            $table->string('ended_reason', 280)->nullable()->after('ended_at');
            $table->foreignId('assigned_by')
                ->nullable()
                ->after('assigned_reason')
                ->constrained('users')
                ->nullOnDelete();
            $table->foreignId('ended_by')
                ->nullable()
                ->after('ended_reason')
                ->constrained('users')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('care_requests', function (Blueprint $table) {
            $table->dropConstrainedForeignId('assigned_provider_id');
            $table->dropConstrainedForeignId('decided_by');
            $table->dropIndex(['status', 'created_at']);
            $table->dropColumn(['assignment_role', 'decision_note', 'decided_at']);
        });

        Schema::table('care_assignments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('assigned_by');
            $table->dropConstrainedForeignId('ended_by');
            $table->dropColumn(['assigned_reason', 'ended_reason']);
        });
    }
};
