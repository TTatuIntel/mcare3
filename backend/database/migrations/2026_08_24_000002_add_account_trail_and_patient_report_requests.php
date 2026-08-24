<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Two additions that back the "complete user dossier" admin surface.
 *
 * 1. `users` gains the account lifecycle trail staff previously had to
 *    reconstruct from the audit log: when the account last signed in, how
 *    often, and who approved / rejected the application (plus the note).
 *    Every column is nullable so existing rows stay valid.
 *
 * 2. `patient_report_requests` holds a customised patient report: the
 *    ticked sections, the patient's consent (OTP or approval link), and the
 *    doctor's signature. Nothing is disclosed until the row reaches `issued`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('last_login_at')->nullable()->after('locked_until');
            $table->string('last_login_ip', 45)->nullable()->after('last_login_at');
            $table->unsignedInteger('login_count')->default(0)->after('last_login_ip');

            // Approval decision trail — previously audit-log only.
            $table->timestamp('approved_at')->nullable()->after('approval_status');
            $table->foreignId('approved_by')
                ->nullable()
                ->after('approved_at')
                ->constrained('users')
                ->nullOnDelete();
            $table->string('approval_note', 280)->nullable()->after('approved_by');
            $table->timestamp('rejected_at')->nullable()->after('approval_note');
            $table->string('rejection_reason', 280)->nullable()->after('rejected_at');
        });

        Schema::create('patient_report_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('patient_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('requested_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('doctor_user_id')->nullable()->constrained('users')->nullOnDelete();

            $table->string('title', 160);
            $table->string('purpose', 280);
            $table->string('recipient', 160)->nullable();

            // Ticked section keys — see App\Support\PatientReportSections.
            $table->json('sections');
            $table->boolean('consent_required')->default(false);
            $table->boolean('signature_required')->default(true);

            // draft | pending_consent | consented | declined | expired
            // | pending_signature | signed | issued | revoked
            $table->string('status', 24)->default('draft');

            // Consent — the plaintext code is never stored.
            $table->string('consent_code_hash')->nullable();
            $table->string('consent_token', 64)->nullable()->unique();
            $table->string('consent_channel', 16)->nullable();
            $table->timestamp('consent_sent_at')->nullable();
            $table->timestamp('consent_expires_at')->nullable();
            $table->unsignedTinyInteger('consent_attempts')->default(0);
            $table->timestamp('consented_at')->nullable();
            $table->string('consent_method', 24)->nullable();
            $table->timestamp('declined_at')->nullable();
            $table->string('decline_reason', 280)->nullable();

            // Doctor sign-off.
            $table->timestamp('signed_at')->nullable();
            $table->string('signature_name', 160)->nullable();
            $table->string('signature_note', 280)->nullable();

            $table->timestamp('issued_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->string('revoke_reason', 280)->nullable();

            // Frozen section payload captured at issue time.
            $table->longText('snapshot')->nullable();

            $table->timestamps();

            $table->index(['patient_user_id', 'status']);
            $table->index(['doctor_user_id', 'status']);
            $table->index(['status', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('patient_report_requests');

        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('approved_by');
            $table->dropColumn([
                'last_login_at',
                'last_login_ip',
                'login_count',
                'approved_at',
                'approval_note',
                'rejected_at',
                'rejection_reason',
            ]);
        });
    }
};
