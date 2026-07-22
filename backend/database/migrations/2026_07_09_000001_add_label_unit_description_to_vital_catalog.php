<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vital_catalog', function (Blueprint $table) {
            $table->string('label', 80)->nullable()->after('vital_key');
            $table->string('unit', 24)->nullable()->after('label');
            $table->string('description', 280)->nullable()->after('unit');
        });
    }

    public function down(): void
    {
        Schema::table('vital_catalog', function (Blueprint $table) {
            $table->dropColumn(['label', 'unit', 'description']);
        });
    }
};
