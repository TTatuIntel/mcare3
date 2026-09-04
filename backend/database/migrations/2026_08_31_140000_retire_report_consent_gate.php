<?php

use App\Models\PatientReportRequest;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Replaces the patient-consent gate with the doctor's signature as the single
 * authorisation for issuing a report.
 *
 * The consent step asked a patient to approve, by one-time code, a disclosure
 * their own clinic was preparing for them — a referral letter, an insurance
 * form. In practice it stalled every report behind an OTP the patient often
 * never saw, and it was the wrong question: the judgement that matters is
 * whether the clinical content is accurate and appropriate to send, which is
 * the doctor's to make, not the patient's. A signature is now required on
 * every report rather than only clinical ones, so removing consent removes a
 * gate without leaving a report ungated.
 *
 * The consent columns stay. Reports issued under the old rules really were
 * consented to, and `consented_at` on those rows is a fact about what happened
 * — dropping it would rewrite history rather than change the workflow.
 *
 * `under_review_*` records an admin parking a signed report they have looked
 * at but are not ready to issue, so a second admin can see it is in hand
 * rather than untouched.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patient_report_requests', function (Blueprint $table) {
            $table->timestamp('under_review_at')->nullable()->after('return_count');
            $table->string('under_review_note', 280)->nullable()->after('under_review_at');
        });

        // Rows mid-flight when the gate was removed. Left alone they would wait
        // forever on a step that no longer exists — nothing in the app can
        // grant consent any more, so they would never reach a doctor.
        DB::table('patient_report_requests')
            ->whereNull('issued_at')
            ->whereIn('status', [
                PatientReportRequest::STATUS_DRAFT,
                PatientReportRequest::STATUS_PENDING_CONSENT,
                PatientReportRequest::STATUS_CONSENTED,
                PatientReportRequest::STATUS_EXPIRED,
            ])
            ->update([
                'status' => PatientReportRequest::STATUS_PENDING_SIGNATURE,
                'signature_required' => true,
                // The challenge is dead; leaving a live hash and token around
                // for a code nothing can redeem is an auth surface with no
                // purpose.
                'consent_code_hash' => null,
                'consent_token' => null,
                'consent_expires_at' => null,
            ]);
    }

    public function down(): void
    {
        Schema::table('patient_report_requests', function (Blueprint $table) {
            $table->dropColumn(['under_review_at', 'under_review_note']);
        });
    }
};
