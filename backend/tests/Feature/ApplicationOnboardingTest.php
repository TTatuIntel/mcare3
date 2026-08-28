<?php

namespace Tests\Feature;

use App\Mail\ApplicationUpdateMail;
use App\Mail\TemporaryCredentialsMail;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * What reaches an applicant who cannot sign in yet.
 *
 * A clinician account is opened by an administrator and sits in
 * pending_approval until it is reviewed. Every message about that review —
 * approved, rejected, or a question — used to be written as an in-app
 * notification to an account that cannot be opened to read it, and the
 * temporary password nobody had ever been told stayed on the administrator's
 * screen. These pin that the decision reaches the person it is about, that
 * approval issues credentials they can actually use, and that a password an
 * administrator has seen can never stay in place.
 */
class ApplicationOnboardingTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $applicant;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Mail::fake();

        $this->admin = User::factory()->role('admin')->create();
        $this->applicant = User::factory()->role('doctor')->create([
            'email' => 'dr.wanjiru@mcare.health',
            'approval_status' => 'pending_approval',
            'password' => Hash::make('opened-by-admin'),
            'must_change_password' => true,
        ]);
    }

    public function test_approval_emails_credentials_the_applicant_can_use(): void
    {
        Sanctum::actingAs($this->admin);

        $this->patchJson("/api/v1/admin/approvals/{$this->applicant->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.email_sent', true);

        Mail::assertSent(
            TemporaryCredentialsMail::class,
            fn (TemporaryCredentialsMail $mail) => $mail->hasTo('dr.wanjiru@mcare.health')
                && $mail->approved
                && $mail->temporaryPassword !== '',
        );

        $fresh = $this->applicant->fresh();
        $this->assertSame('active', $fresh->approval_status);
        $this->assertTrue(
            (bool) $fresh->must_change_password,
            'a password the administrator issued is temporary by definition',
        );
    }

    public function test_the_emailed_password_is_the_one_that_works(): void
    {
        Sanctum::actingAs($this->admin);
        $this->patchJson("/api/v1/admin/approvals/{$this->applicant->id}/approve")
            ->assertOk();

        $sent = null;
        Mail::assertSent(TemporaryCredentialsMail::class, function ($mail) use (&$sent) {
            $sent = $mail->temporaryPassword;

            return true;
        });

        // The credentials in the email sign in, and the app is told the
        // password must be replaced before anything else happens.
        $this->postJson('/api/v1/auth/login', [
            'identifier' => 'dr.wanjiru@mcare.health',
            'password' => $sent,
        ])->assertOk()->assertJsonPath('data.user.must_change_password', true);

        // Whatever the account was opened with is dead.
        $this->postJson('/api/v1/auth/login', [
            'identifier' => 'dr.wanjiru@mcare.health',
            'password' => 'opened-by-admin',
        ])->assertStatus(401);
    }

    public function test_changing_the_password_lifts_the_requirement(): void
    {
        Sanctum::actingAs($this->admin);
        $this->patchJson("/api/v1/admin/approvals/{$this->applicant->id}/approve")->assertOk();

        $sent = null;
        Mail::assertSent(TemporaryCredentialsMail::class, function ($mail) use (&$sent) {
            $sent = $mail->temporaryPassword;

            return true;
        });

        Sanctum::actingAs($this->applicant->fresh());
        $this->postJson('/api/v1/auth/change-password', [
            'current_password' => $sent,
            'new_password' => 'their-own-choice-9',
        ])->assertOk();

        $this->assertFalse(
            (bool) $this->applicant->fresh()->must_change_password,
            'once they choose their own, nothing is being forced any more',
        );
    }

    public function test_a_request_for_information_reaches_their_inbox(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/approvals/{$this->applicant->id}/request-info", [
            'message' => 'Please attach your current practising licence.',
        ])->assertOk()->assertJsonPath('data.email_sent', true);

        Mail::assertSent(
            ApplicationUpdateMail::class,
            fn (ApplicationUpdateMail $mail) => $mail->hasTo('dr.wanjiru@mcare.health')
                && $mail->kind === ApplicationUpdateMail::KIND_INFO_REQUESTED
                && str_contains($mail->message, 'practising licence'),
        );

        $this->assertSame(
            'pending_approval',
            $this->applicant->fresh()->approval_status,
            'asking a question does not decide the application',
        );
    }

    public function test_a_rejection_says_why_by_email(): void
    {
        Sanctum::actingAs($this->admin);

        $this->patchJson("/api/v1/admin/approvals/{$this->applicant->id}/reject", [
            'reason' => 'Licence number could not be verified.',
        ])->assertOk()->assertJsonPath('data.email_sent', true);

        Mail::assertSent(
            ApplicationUpdateMail::class,
            fn (ApplicationUpdateMail $mail) => $mail->hasTo('dr.wanjiru@mcare.health')
                && $mail->kind === ApplicationUpdateMail::KIND_REJECTED,
        );
    }

    public function test_an_administrator_reset_also_lands_in_their_inbox(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson("/api/v1/admin/users/{$this->applicant->id}/password-reset")
            ->assertOk()
            ->assertJsonPath('data.email_sent', true);

        Mail::assertSent(
            TemporaryCredentialsMail::class,
            fn (TemporaryCredentialsMail $mail) => $mail->hasTo('dr.wanjiru@mcare.health')
                && ! $mail->approved,
        );

        $this->assertTrue((bool) $this->applicant->fresh()->must_change_password);
    }

    public function test_approval_is_not_gated_on_a_credential_document(): void
    {
        $this->assertNull(
            $this->applicant->credential_document_path,
            'nothing has been uploaded for this applicant',
        );

        Sanctum::actingAs($this->admin);

        $this->patchJson("/api/v1/admin/approvals/{$this->applicant->id}/approve")
            ->assertOk();

        $this->assertSame('active', $this->applicant->fresh()->approval_status);
    }

    public function test_an_applicant_can_still_start_their_own_reset(): void
    {
        // Self-service exists and is untouched by any of the above: the
        // account owner is never dependent on an administrator to get back in.
        $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'dr.wanjiru@mcare.health',
        ])->assertOk();
    }
}
