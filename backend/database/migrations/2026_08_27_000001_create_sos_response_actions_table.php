<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a responder actually did during an emergency.
 *
 * Status changes alone ("active" → "acknowledged" → "resolved") say who ended
 * an SOS but never how it was worked. A responder who called the patient,
 * pulled up their location and handed the case to a provider left no record
 * of any of it, so a handover mid-emergency — or any review afterwards —
 * started from nothing. Each row here is one step, appended and never edited.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sos_response_actions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sos_event_id')
                ->constrained('sos_events')
                ->cascadeOnDelete();
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // Who acted, captured at the time: a responder's role or name can
            // change later, and the trail must still read correctly.
            $table->string('actor_name', 160);
            $table->string('action', 40);
            $table->string('detail', 300)->nullable();
            $table->timestamps();

            // The trail is always read for one event, newest last.
            $table->index(['sos_event_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sos_response_actions');
    }
};
