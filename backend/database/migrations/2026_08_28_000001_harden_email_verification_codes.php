<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('email_verification_codes', function (Blueprint $table) {
            $table->string('code', 255)->change();
            $table->unsignedTinyInteger('attempts')->default(0)->after('purpose');
            $table->index(['user_id', 'purpose', 'created_at'], 'verification_code_lookup');
        });
    }

    public function down(): void
    {
        Schema::table('email_verification_codes', function (Blueprint $table) {
            $table->dropIndex('verification_code_lookup');
            $table->dropColumn('attempts');
            $table->string('code', 6)->change();
        });
    }
};
