<?php

use App\Support\SmsSender;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('phone_e164', 24)->nullable()->after('phone')->index();
        });

        $sms = app(SmsSender::class);
        DB::table('users')
            ->select(['id', 'phone'])
            ->whereNotNull('phone')
            ->orderBy('id')
            ->chunkById(500, function ($users) use ($sms): void {
                foreach ($users as $user) {
                    DB::table('users')->where('id', $user->id)->update([
                        'phone_e164' => $sms->normalize($user->phone),
                    ]);
                }
            });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('phone_e164');
        });
    }
};
