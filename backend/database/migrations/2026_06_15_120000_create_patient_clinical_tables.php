<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Patient clinical domain schema.
 *
 * Tables added in this migration mirror the Flutter shared models 1:1
 * (lib/shared/models/*). They are owned by `users.id` so the same user
 * row drives every role.
 *
 * Naming convention: snake_case. Enum-style columns are kept as plain
 * strings with documented allowed values — Flutter normalises them on
 * the way in.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ----------------------------------------------------------------
        // VITAL READINGS — every measurement the patient submits.
        // ----------------------------------------------------------------
        Schema::create('vital_readings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // bloodPressure | heartRate | bloodOxygen | temperature |
            // bloodGlucose | respiratoryRate | weight
            $table->string('vital_key', 32);
            $table->decimal('value', 7, 2);
            // Blood pressure stores diastolic here; null for other vitals.
            $table->decimal('secondary_value', 7, 2)->nullable();
            // normal | warning | critical | unknown
            $table->string('risk', 16)->default('unknown');
            $table->timestamp('recorded_at');
            $table->text('note')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'vital_key', 'recorded_at']);
        });

        // ----------------------------------------------------------------
        // PER-PATIENT VITAL RANGE OVERRIDES (doctor-set).
        // Falls back to system defaults from the vital_catalog table.
        // ----------------------------------------------------------------
        Schema::create('vital_range_overrides', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('vital_key', 32);
            $table->decimal('normal_min', 7, 2);
            $table->decimal('normal_max', 7, 2);
            $table->decimal('warning_low', 7, 2);
            $table->decimal('warning_high', 7, 2);
            $table->decimal('critical_low', 7, 2);
            $table->decimal('critical_high', 7, 2);
            $table->foreignId('set_by_user_id')->nullable()->constrained('users');
            $table->timestamps();
            $table->unique(['user_id', 'vital_key']);
        });

        // ----------------------------------------------------------------
        // SYSTEM-WIDE VITAL CATALOG (admin-managed defaults).
        // ----------------------------------------------------------------
        Schema::create('vital_catalog', function (Blueprint $table) {
            $table->id();
            $table->string('vital_key', 32)->unique();
            $table->decimal('normal_min', 7, 2);
            $table->decimal('normal_max', 7, 2);
            $table->decimal('warning_low', 7, 2);
            $table->decimal('warning_high', 7, 2);
            $table->decimal('critical_low', 7, 2);
            $table->decimal('critical_high', 7, 2);
            $table->boolean('enabled')->default(true);
            $table->timestamps();
        });

        // ----------------------------------------------------------------
        // MEDICATIONS + DOSES
        // ----------------------------------------------------------------
        Schema::create('medications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('dosage');                 // "500 mg"
            $table->string('frequency');              // "Twice daily"
            $table->string('form')->nullable();       // "Tablet"
            $table->text('instructions')->nullable();
            $table->string('prescribed_by')->nullable();
            $table->foreignId('prescribed_by_user_id')->nullable()->constrained('users');
            $table->date('start_date');
            $table->date('end_date')->nullable();
            $table->date('expiry_date')->nullable();
            $table->unsignedSmallInteger('refills_left')->nullable();
            // doctorPrescribed | patientAdded
            $table->string('source', 32)->default('doctorPrescribed');
            $table->boolean('active')->default(true);
            $table->timestamps();
            $table->index(['user_id', 'active']);
        });

        Schema::create('medication_doses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('medication_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->timestamp('scheduled_at');
            $table->timestamp('taken_at')->nullable();
            // pending | taken | skipped | missed
            $table->string('status', 16)->default('pending');
            $table->timestamps();
            $table->index(['user_id', 'scheduled_at']);
        });

        // ----------------------------------------------------------------
        // APPOINTMENTS
        // ----------------------------------------------------------------
        Schema::create('appointments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // Provider may not yet be a registered user.
            $table->foreignId('doctor_user_id')->nullable()->constrained('users');
            $table->string('doctor_name');
            $table->string('doctor_specialty')->nullable();
            $table->timestamp('scheduled_at');
            $table->unsignedSmallInteger('duration_minutes')->default(30);
            // inPerson | virtual | phone
            $table->string('type', 16)->default('inPerson');
            // scheduled | confirmed | completed | cancelled
            $table->string('status', 16)->default('scheduled');
            $table->string('reason')->nullable();
            $table->string('location_or_link')->nullable();
            $table->string('cancellation_reason')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'scheduled_at']);
            $table->index(['doctor_user_id', 'scheduled_at']);
        });

        // ----------------------------------------------------------------
        // MEDICAL DOCUMENTS
        // ----------------------------------------------------------------
        Schema::create('medical_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            // labResult | prescription | imaging | discharge |
            // consultationNote | other
            $table->string('category', 32)->default('other');
            // pdf | image | doc | other
            $table->string('file_type', 16)->default('other');
            $table->string('storage_path')->nullable();
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->string('uploaded_by');
            $table->text('description')->nullable();
            $table->foreignId('shared_with_doctor_id')->nullable()->constrained('users');
            $table->timestamp('uploaded_at');
            $table->timestamps();
            $table->index(['user_id', 'uploaded_at']);
        });

        // ----------------------------------------------------------------
        // MESSAGING — conversations + chat_messages.
        // Each conversation is a 1:1 thread between the patient and a
        // staff participant. Group threads use the same schema.
        // ----------------------------------------------------------------
        Schema::create('conversations', function (Blueprint $table) {
            $table->id();
            // Owner — the patient view loads only conversations they're in.
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // Counterparty (the doctor / assistant / admin / external doctor).
            $table->foreignId('participant_user_id')->nullable()->constrained('users');
            $table->string('participant_name');
            // doctor | patient | admin | assistant | external_doctor
            $table->string('participant_role', 32);
            $table->string('participant_specialty')->nullable();
            $table->unsignedInteger('unread_count')->default(0);
            $table->timestamp('last_message_at')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'last_message_at']);
        });

        Schema::create('chat_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('conversation_id')->constrained()->cascadeOnDelete();
            // 'me' on the client maps to the authenticated user_id here.
            $table->foreignId('sender_user_id')->nullable()->constrained('users');
            $table->text('body');
            $table->boolean('read')->default(false);
            $table->timestamp('sent_at');
            $table->timestamps();
            $table->index(['conversation_id', 'sent_at']);
        });

        // ----------------------------------------------------------------
        // NOTIFICATIONS — unified pipeline (§9.5 / monitoring engine memory).
        // ----------------------------------------------------------------
        Schema::create('app_notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // vitalAlert | appointment | medication | message | document |
            // report | careRequest | approval | sos | assignment | profile |
            // system
            $table->string('kind', 32);
            $table->string('title');
            $table->text('body');
            $table->string('action_route')->nullable();
            // JSON-encoded route arguments (string / vital key / id).
            $table->json('action_arguments')->nullable();
            $table->boolean('read')->default(false);
            $table->boolean('resolved')->default(false);
            $table->timestamp('resolved_at')->nullable();
            $table->timestamp('created_at')->nullable();
            $table->timestamp('updated_at')->nullable();
            $table->index(['user_id', 'created_at']);
            $table->index(['user_id', 'read']);
        });

        // ----------------------------------------------------------------
        // SUPPORT TICKETS + REPLIES
        // ----------------------------------------------------------------
        Schema::create('support_tickets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('subject');
            $table->text('description');
            // technical | medical | billing | account | other
            $table->string('category', 16)->default('other');
            // low | normal | high | urgent
            $table->string('priority', 16)->default('normal');
            // open | inProgress | resolved | closed
            $table->string('status', 16)->default('open');
            $table->foreignId('assigned_to')->nullable()->constrained('users');
            $table->timestamp('updated_at_app')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'status']);
        });

        Schema::create('support_ticket_replies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ticket_id')->constrained('support_tickets')->cascadeOnDelete();
            $table->foreignId('author_user_id')->nullable()->constrained('users');
            $table->string('author');
            $table->boolean('is_staff')->default(false);
            $table->text('body');
            $table->timestamp('sent_at');
            $table->timestamps();
            $table->index(['ticket_id', 'sent_at']);
        });

        // ----------------------------------------------------------------
        // SOS — events + (emergency contacts already exist).
        // ----------------------------------------------------------------
        Schema::create('sos_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // medical | accident | fall | panic | other
            $table->string('kind', 16);
            // active | acknowledged | resolved | falseAlarm
            $table->string('status', 16)->default('active');
            $table->string('location_label')->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->text('note')->nullable();
            $table->string('responded_by')->nullable();
            $table->timestamp('triggered_at');
            $table->timestamp('responded_at')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'triggered_at']);
        });

        // ----------------------------------------------------------------
        // CARE TEAM — providers (staff users with extra clinical metadata)
        // + patient↔provider care requests + active assignments.
        // ----------------------------------------------------------------
        Schema::create('care_providers', function (Blueprint $table) {
            $table->id();
            // Optionally linked to a `users` row. For now we keep them
            // free-standing so admins can seed providers before they sign up.
            $table->foreignId('user_id')->nullable()->constrained('users');
            $table->string('name');
            $table->string('specialty');
            $table->string('facility')->nullable();
            $table->unsignedSmallInteger('years_experience')->default(0);
            $table->decimal('rating', 3, 2)->default(0);
            $table->unsignedInteger('total_reviews')->default(0);
            $table->text('bio')->nullable();
            $table->json('languages')->nullable();
            $table->timestamps();
        });

        Schema::create('care_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('provider_id')->constrained('care_providers')->cascadeOnDelete();
            $table->string('provider_name');
            $table->string('provider_specialty')->nullable();
            $table->string('reason')->nullable();
            // pending | approved | rejected | cancelled
            $table->string('status', 16)->default('pending');
            $table->timestamps();
            $table->index(['user_id', 'status']);
        });

        Schema::create('care_assignments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('patient_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('provider_id')->constrained('care_providers')->cascadeOnDelete();
            // Primary | Consulting | …
            $table->string('role')->default('Primary');
            $table->timestamp('assigned_at');
            $table->timestamp('ended_at')->nullable();
            $table->timestamps();
            $table->unique(['patient_user_id', 'provider_id', 'role']);
        });

        // ----------------------------------------------------------------
        // VITAL REPORT REQUESTS — patient asks for a window summary; the
        // doctor → assistant → admin escalation chain is encoded as
        // `current_responder` + SLA timers.
        // ----------------------------------------------------------------
        Schema::create('vital_report_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->date('range_from');
            $table->date('range_to');
            $table->json('vitals');                       // array of vital_key
            $table->text('note')->nullable();
            // pending | fulfilled | cancelled
            $table->string('status', 16)->default('pending');
            // doctor | mcareAssistant | admin
            $table->string('current_responder', 32)->default('doctor');
            $table->timestamp('last_escalated_at')->nullable();
            $table->timestamp('responded_at')->nullable();
            $table->string('responded_by')->nullable();
            $table->text('response_note')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'status']);
            $table->index(['status', 'current_responder']);
        });

        // ----------------------------------------------------------------
        // mCARE ASSISTANT PERMISSIONS — per-user grants delegated by admin.
        // ----------------------------------------------------------------
        Schema::create('assistant_permissions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('permission_key', 64);
            $table->foreignId('granted_by_user_id')->nullable()->constrained('users');
            $table->timestamps();
            $table->unique(['user_id', 'permission_key']);
        });

        // ----------------------------------------------------------------
        // AUDIT TRAIL (activity + security).
        // ----------------------------------------------------------------
        Schema::create('audit_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('actor_user_id')->nullable()->constrained('users');
            $table->string('actor_label');
            $table->string('action');
            $table->string('target')->nullable();
            // activity | security
            $table->string('category', 16)->default('activity');
            $table->json('meta')->nullable();
            $table->timestamp('happened_at');
            $table->timestamps();
            $table->index(['category', 'happened_at']);
        });

        // ----------------------------------------------------------------
        // CLINICAL REPORTS (doctor-authored).
        // ----------------------------------------------------------------
        Schema::create('clinical_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('patient_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('author_user_id')->nullable()->constrained('users');
            $table->string('title');
            $table->longText('body')->nullable();
            $table->boolean('published')->default(false);
            $table->timestamp('published_at')->nullable();
            $table->timestamps();
            $table->index(['patient_user_id', 'created_at']);
        });

        // ----------------------------------------------------------------
        // FCM TOKENS — push registration per device.
        // ----------------------------------------------------------------
        Schema::create('fcm_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('token', 512);
            $table->string('platform', 16)->nullable(); // android | ios | web
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();
            $table->unique('token');
        });

        // ----------------------------------------------------------------
        // SYSTEM SETTINGS — singleton-style key/value flags for the
        // Admin → System screen.
        // ----------------------------------------------------------------
        Schema::create('system_settings', function (Blueprint $table) {
            $table->id();
            $table->string('key', 64)->unique();
            $table->string('title');
            $table->string('description')->nullable();
            $table->boolean('value')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_settings');
        Schema::dropIfExists('fcm_tokens');
        Schema::dropIfExists('clinical_reports');
        Schema::dropIfExists('audit_entries');
        Schema::dropIfExists('assistant_permissions');
        Schema::dropIfExists('vital_report_requests');
        Schema::dropIfExists('care_assignments');
        Schema::dropIfExists('care_requests');
        Schema::dropIfExists('care_providers');
        Schema::dropIfExists('sos_events');
        Schema::dropIfExists('support_ticket_replies');
        Schema::dropIfExists('support_tickets');
        Schema::dropIfExists('app_notifications');
        Schema::dropIfExists('chat_messages');
        Schema::dropIfExists('conversations');
        Schema::dropIfExists('medical_documents');
        Schema::dropIfExists('appointments');
        Schema::dropIfExists('medication_doses');
        Schema::dropIfExists('medications');
        Schema::dropIfExists('vital_catalog');
        Schema::dropIfExists('vital_range_overrides');
        Schema::dropIfExists('vital_readings');
    }
};
