<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A meal plan used to be a single standing instruction stamped with the
     * moment a clinician assigned it. Nutrition care is a timetable, so a plan
     * now also carries the day it is meant to be eaten, the time of day, the
     * condition it was prescribed for, and whether the patient followed it.
     *
     * Every column is nullable or defaulted: rows written before this migration
     * stay valid and fall back to `assigned_at` as their scheduled day.
     */
    public function up(): void
    {
        Schema::table('meal_plans', function (Blueprint $table) {
            $table->date('scheduled_for')->nullable()->after('meal_type');
            $table->string('serve_time', 5)->nullable()->after('scheduled_for');
            $table->string('condition_tag', 120)->nullable()->after('serve_time');
            $table->json('items')->nullable()->after('description');
            $table->string('source', 16)->default('care_team')->after('assigned_by_user_id');
            $table->string('adherence', 16)->default('pending')->after('notes');
            $table->timestamp('logged_at')->nullable()->after('adherence');
            $table->text('patient_note')->nullable()->after('logged_at');

            $table->index(['patient_user_id', 'scheduled_for'], 'meal_plans_patient_day_idx');
        });
    }

    public function down(): void
    {
        Schema::table('meal_plans', function (Blueprint $table) {
            $table->dropIndex('meal_plans_patient_day_idx');
            $table->dropColumn([
                'scheduled_for',
                'serve_time',
                'condition_tag',
                'items',
                'source',
                'adherence',
                'logged_at',
                'patient_note',
            ]);
        });
    }
};
