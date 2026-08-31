<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A short-lived log of "something you can see has changed".
 *
 * The WebSocket path (Reverb) delivers these same signals in milliseconds,
 * but it only delivers them while a socket server and a queue worker are
 * both up. When either is not — a local XAMPP box, a restart, a phone that
 * dropped its connection — the app used to fall back to re-fetching whole
 * role sessions on a 30-second timer, which is what "I have to refresh"
 * feels like.
 *
 * So every signal is also written here, addressed to the same channels the
 * broadcast uses. A client polls for rows newer than the last id it saw and
 * learns exactly which data domains changed, cheaply enough to ask every few
 * seconds. Rows are pruned after minutes: this is a delivery buffer, never a
 * record. Nothing clinical is stored — a domain name and a channel only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('realtime_events', function (Blueprint $table) {
            $table->id();
            // Channel name without the `private-` prefix, e.g. `user.7`.
            $table->string('channel', 64);
            // Client data domains, comma separated (`vitals,alerts`).
            $table->string('domains', 255);
            $table->string('action', 32);
            $table->string('resource_type', 64);
            $table->string('resource_id', 64)->nullable();
            $table->timestamp('created_at')->useCurrent();

            // The only read: "rows for these channels newer than this id".
            $table->index(['channel', 'id']);
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('realtime_events');
    }
};
