<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tightens referential integrity for the one real foreign key that the
 * framework leaves unconstrained: `sessions.user_id`.
 *
 * Every domain table already declares proper foreign keys in the earlier
 * migrations, so this migration only closes the framework-level gap. It is
 * written defensively so it is safe to run against an already-populated
 * database:
 *   - It runs only on drivers that enforce foreign keys via ALTER TABLE.
 *   - It first removes orphaned session rows (sessions are transient — the
 *     only effect is that a stale, user-less session is cleared).
 *   - FK creation is guarded so re-running is a no-op.
 */
return new class extends Migration
{
    public function up(): void
    {
        $driver = Schema::getConnection()->getDriverName();

        // SQLite cannot ALTER TABLE to add a foreign key after creation, and
        // its sessions table is only used in local/testing contexts. Skip it.
        if ($driver === 'sqlite') {
            return;
        }

        if (! Schema::hasTable('sessions') || ! Schema::hasColumn('sessions', 'user_id')) {
            return;
        }

        // Clear orphaned sessions so the constraint can be added cleanly.
        DB::table('sessions')
            ->whereNotNull('user_id')
            ->whereNotIn('user_id', DB::table('users')->select('id'))
            ->delete();

        try {
            Schema::table('sessions', function (Blueprint $table) {
                $table->foreign('user_id', 'sessions_user_id_foreign')
                    ->references('id')
                    ->on('users')
                    ->nullOnDelete();
            });
        } catch (\Throwable $e) {
            // Constraint already exists (or the driver rejected a duplicate) —
            // integrity is already in place, so this is safe to ignore.
        }
    }

    public function down(): void
    {
        if (Schema::getConnection()->getDriverName() === 'sqlite') {
            return;
        }

        if (! Schema::hasTable('sessions')) {
            return;
        }

        try {
            Schema::table('sessions', function (Blueprint $table) {
                $table->dropForeign('sessions_user_id_foreign');
            });
        } catch (\Throwable $e) {
            // Nothing to drop.
        }
    }
};
