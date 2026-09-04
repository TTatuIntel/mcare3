<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Turns a patient's requests into work the care team can actually share.
 *
 * A vital report request was addressed to one responder at a time and answered
 * by whoever happened to open it. Everyone assigned to the patient could see
 * it, nobody owned it, and two clinicians could — and did — write the same
 * report twice. There was also no record of who picked it up, only who
 * finished it, so a request sitting untouched looked exactly like one being
 * worked on.
 *
 * Three pieces fix that:
 *
 * 1. `vital_report_requests` gains a claim. The whole care team still sees the
 *    request; exactly one member can hold it, and holding it is what
 *    authorises finishing it. `document_id` links the request to the report it
 *    produced, so "resolved" points at something the patient can open.
 *
 * 2. `request_activity_events` is the trail — claimed, released, escalated,
 *    resolved — kept beside the request rather than in the audit log, because
 *    the patient reads this one too.
 *
 * 3. `document_requests` is the mirror of a vital report request for
 *    everything else in the record: the patient asking the team, or one named
 *    doctor, for a document they do not have. Same claim, same trail, same
 *    close-out into their documents list.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vital_report_requests', function (Blueprint $table) {
            // Who is working on it. Null while it sits in the shared queue.
            $table->foreignId('claimed_by')
                ->nullable()
                ->after('current_responder')
                ->constrained('users')
                ->nullOnDelete();
            // Denormalised so the patient sees a name without a join through
            // staff records they are not allowed to read.
            $table->string('claimed_by_name')->nullable()->after('claimed_by');
            $table->timestamp('claimed_at')->nullable()->after('claimed_by_name');
            $table->timestamp('resolved_at')->nullable()->after('responded_at');

            // The report that closed this request out, filed in the patient's
            // documents. Nulled rather than cascaded: losing the file must not
            // silently delete the record that it was produced.
            $table->foreignId('document_id')
                ->nullable()
                ->after('response_note')
                ->constrained('medical_documents')
                ->nullOnDelete();

            $table->index(['claimed_by', 'status']);
        });

        Schema::create('request_activity_events', function (Blueprint $table) {
            $table->id();
            // Polymorphic: vital report requests and document requests share
            // one timeline shape, and a third request type will too.
            $table->morphs('subject');
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            // Frozen at write time — the trail must still read correctly after
            // the actor leaves or is renamed.
            $table->string('actor_label');
            // opened | claimed | released | escalated | resolved | declined |
            // cancelled | note
            $table->string('action', 24);
            $table->text('note')->nullable();
            $table->timestamp('happened_at');
            $table->timestamps();
            $table->index(['subject_type', 'subject_id', 'happened_at'], 'raq_subject_time_idx');
        });

        Schema::create('document_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('title');
            // Same camelCase catalogue the app and medical_documents use.
            $table->string('category', 32)->default('other');
            $table->text('note')->nullable();
            // team | doctor — who the patient addressed it to. A team request
            // is answerable by anyone on the caseload; a doctor request is
            // still visible to the team but names who it is waiting on.
            $table->string('target', 16)->default('team');
            $table->foreignId('target_doctor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->date('needed_by')->nullable();
            // pending | in_progress | fulfilled | declined | cancelled
            $table->string('status', 16)->default('pending');
            $table->foreignId('claimed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('claimed_by_name')->nullable();
            $table->timestamp('claimed_at')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->string('resolved_by_name')->nullable();
            $table->text('resolution_note')->nullable();
            $table->string('decline_reason', 280)->nullable();
            $table->foreignId('document_id')
                ->nullable()
                ->constrained('medical_documents')
                ->nullOnDelete();
            $table->timestamps();
            $table->index(['user_id', 'status']);
            $table->index(['status', 'target_doctor_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('document_requests');
        Schema::dropIfExists('request_activity_events');

        Schema::table('vital_report_requests', function (Blueprint $table) {
            $table->dropForeign(['claimed_by']);
            $table->dropForeign(['document_id']);
            $table->dropIndex(['claimed_by', 'status']);
            $table->dropColumn([
                'claimed_by',
                'claimed_by_name',
                'claimed_at',
                'resolved_at',
                'document_id',
            ]);
        });
    }
};
