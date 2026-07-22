<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Adds a short, human-friendly access code alongside the long URL token so a
 * patient can read the code to an external doctor over the phone during an
 * emergency. Nullable so existing rows stay valid.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('external_access_tokens', function (Blueprint $table) {
            $table->string('access_code', 12)->nullable()->unique()->after('token');
        });
    }

    public function down(): void
    {
        Schema::table('external_access_tokens', function (Blueprint $table) {
            $table->dropUnique(['access_code']);
            $table->dropColumn('access_code');
        });
    }
};
