<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Announcements — admin / mCare-assistant authored in-app messages broadcast
 * to a target audience. Rendered on patient + doctor dashboards.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('announcements', function (Blueprint $table) {
            $table->id();
            $table->string('title', 160);
            $table->text('body');
            // all | patients | doctors | healthworkers | mcare_assistant | admin
            $table->string('audience', 64)->default('all');
            $table->string('cta_label', 64)->nullable();
            $table->string('cta_url', 512)->nullable();
            $table->string('image_path', 512)->nullable();
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            $table->boolean('is_published')->default(false);
            $table->foreignId('created_by_user_id')->nullable()->constrained('users');
            $table->timestamps();
            $table->index(['is_published', 'starts_at', 'ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('announcements');
    }
};
