<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('patient_tracked_vitals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('vital_key');
            $table->timestamps();
            $table->unique(['user_id', 'vital_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('patient_tracked_vitals');
    }
};
