<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('patient_health_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('blood_type')->default('unknown');
            $table->string('gender')->default('preferNotToSay');
            $table->date('date_of_birth');
            $table->decimal('height_cm', 5, 2);
            $table->decimal('weight_kg', 5, 2);
            $table->json('allergies')->nullable();
            $table->json('chronic_conditions')->nullable();
            $table->json('current_medications')->nullable();
            $table->string('address')->nullable();
            $table->boolean('location_consent')->default(false);
            $table->boolean('no_known_allergies')->default(false);
            $table->boolean('no_current_medications')->default(false);
            $table->timestamps();
        });

        Schema::create('emergency_contacts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('relationship');
            $table->string('phone');
            $table->string('email')->nullable();
            $table->unsignedTinyInteger('priority')->default(1);
            $table->timestamps();
        });

        Schema::create('patient_assigned_vitals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('vital_key');
            $table->timestamps();
            $table->unique(['user_id', 'vital_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('patient_assigned_vitals');
        Schema::dropIfExists('emergency_contacts');
        Schema::dropIfExists('patient_health_profiles');
    }
};
