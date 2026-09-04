<?php

use App\Http\Controllers\Api\V1\Admin\VitalReportRequestsController as AdminVitalReportRequestsController;
use App\Http\Controllers\Api\V1\Admin\AdminAlertsController;
use App\Http\Controllers\Api\V1\Admin\AdminSessionController;
use App\Http\Controllers\Api\V1\Admin\AnalyticsController as AdminAnalyticsController;
use App\Http\Controllers\Api\V1\Admin\AnnouncementsController as AdminAnnouncementsController;
use App\Http\Controllers\Api\V1\Admin\ApprovalsController as AdminApprovalsController;
use App\Http\Controllers\Api\V1\Admin\AssignmentsController as AdminAssignmentsController;
use App\Http\Controllers\Api\V1\Admin\AuditController as AdminAuditController;
use App\Http\Controllers\Api\V1\Admin\CareRequestsController as AdminCareRequestsController;
use App\Http\Controllers\Api\V1\Admin\ConversationsController as AdminConversationsController;
use App\Http\Controllers\Api\V1\Admin\NotificationsController as AdminNotificationsController;
use App\Http\Controllers\Api\V1\Admin\PatientDocumentsController as AdminPatientDocumentsController;
use App\Http\Controllers\Api\V1\Admin\PatientReportsController as AdminPatientReportsController;
use App\Http\Controllers\Api\V1\Admin\PatientsController as AdminPatientsController;
use App\Http\Controllers\Api\V1\Admin\PermissionsController as AdminPermissionsController;
use App\Http\Controllers\Api\V1\Admin\SecurityIncidentsController as AdminSecurityIncidentsController;
use App\Http\Controllers\Api\V1\Admin\SupportTicketsController as AdminSupportTicketsController;
use App\Http\Controllers\Api\V1\Admin\SystemSettingsController as AdminSystemSettingsController;
use App\Http\Controllers\Api\V1\Admin\UserProfileController as AdminUserProfileController;
use App\Http\Controllers\Api\V1\Admin\UsersController as AdminUsersController;
use App\Http\Controllers\Api\V1\Admin\VitalCatalogController as AdminVitalCatalogController;
use App\Http\Controllers\Api\V1\AdminSosController;
use App\Http\Controllers\Api\V1\AppointmentsController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CareController;
use App\Http\Controllers\Api\V1\DoctorAlertsController;
use App\Http\Controllers\Api\V1\DoctorAppointmentsController;
use App\Http\Controllers\Api\V1\DoctorMealPlansController;
use App\Http\Controllers\Api\V1\DoctorMessagesController;
use App\Http\Controllers\Api\V1\DoctorPatientController;
use App\Http\Controllers\Api\V1\DoctorPrescriptionsController;
use App\Http\Controllers\Api\V1\DoctorReportsController;
use App\Http\Controllers\Api\V1\DoctorReportSignaturesController;
use App\Http\Controllers\Api\V1\DoctorSessionController;
use App\Http\Controllers\Api\V1\DoctorSosController;
use App\Http\Controllers\Api\V1\DoctorVitalCatalogController;
use App\Http\Controllers\Api\V1\DoctorDocumentRequestsController;
use App\Http\Controllers\Api\V1\DoctorVitalReportRequestsController;
use App\Http\Controllers\Api\V1\DocumentRequestsController;
use App\Http\Controllers\Api\V1\DocumentsController;
use App\Http\Controllers\Api\V1\ExternalBroadcastAuthController;
use App\Http\Controllers\Api\V1\ExternalDoctorController;
use App\Http\Controllers\Api\V1\ExternalRealtimePulseController;
use App\Http\Controllers\Api\V1\FcmTokenController;
use App\Http\Controllers\Api\V1\MedicationsController;
use App\Http\Controllers\Api\V1\MessagesController;
use App\Http\Controllers\Api\V1\NotificationsController;
use App\Http\Controllers\Api\V1\PatientChartController;
use App\Http\Controllers\Api\V1\PatientExternalAccessController;
use App\Http\Controllers\Api\V1\PatientMealPlansController;
use App\Http\Controllers\Api\V1\PatientProfileController;
use App\Http\Controllers\Api\V1\PatientRecordController;
use App\Http\Controllers\Api\V1\PatientReportConsentsController;
use App\Http\Controllers\Api\V1\PatientSessionController;
use App\Http\Controllers\Api\V1\PatientTrackedVitalsController;
use App\Http\Controllers\Api\V1\PublicConfigController;
use App\Http\Controllers\Api\V1\RealtimePulseController;
use App\Http\Controllers\Api\V1\SosAssignmentCandidatesController;
use App\Http\Controllers\Api\V1\SosController;
use App\Http\Controllers\Api\V1\SosHandoverController;
use App\Http\Controllers\Api\V1\SosResponseActionsController;
use App\Http\Controllers\Api\V1\StaffNotificationStateController;
use App\Http\Controllers\Api\V1\SupportController;
use App\Http\Controllers\Api\V1\UserSettingsController;
use App\Http\Controllers\Api\V1\VitalReportRequestsController;
use App\Http\Controllers\Api\V1\VitalsController;
use Illuminate\Support\Facades\Route;

// Public client configuration. Unauthenticated by necessity: the app reads it
// before anyone can sign in. Carries only values that are public by design
// (OAuth client IDs), never secrets. Throttled as a plain anonymous endpoint.
Route::get('config', PublicConfigController::class)->middleware('throttle:30,1');

Route::prefix('auth')->group(function () {
    // Brute-force protection per README §6.5: 5/min/IP + 5/15min/email.
    // Defined as the named limiter `auth-login` in AppServiceProvider.
    Route::middleware('throttle:auth-login')->group(function () {
        Route::post('register', [AuthController::class, 'register']);
        Route::post('login', [AuthController::class, 'login']);
        Route::post('forgot-password', [AuthController::class, 'forgotPassword']);
        Route::post('reset-password', [AuthController::class, 'resetPassword']);
        // Exchanges an SMS reset OTP for a real reset token. Brute-forceable
        // 6-digit surface, so it shares the login limiter (5/min/IP).
        Route::post('verify-reset-otp', [AuthController::class, 'verifyResetOtp']);
        Route::post('verify-otp', [AuthController::class, 'verifyOtp']);
        Route::post('accept-invite', [AuthController::class, 'acceptInvite']);
    });
    // The emailed verification link. Public and GET because a mail client on
    // a device that has never signed in has to be able to follow it; the
    // token in the path is the whole credential, so it is single-use and
    // short-lived. Throttled as an anonymous guessable surface.
    Route::get('verify-email/{token}', [AuthController::class, 'verifyEmailLink'])
        ->where('token', '[A-Za-z0-9]{16,64}')
        ->middleware('throttle:20,1')
        ->name('auth.verify-email');

    Route::post('google', [AuthController::class, 'google'])->middleware('throttle:20,1');
    Route::get('google/redirect', [AuthController::class, 'googleRedirect']);
    Route::get('google/callback', [AuthController::class, 'googleCallback']);
    Route::post('apple/challenge', [AuthController::class, 'appleChallenge'])->middleware('throttle:20,1');
    Route::post('apple', [AuthController::class, 'apple'])->middleware('throttle:20,1');

    Route::middleware('auth:sanctum')->group(function () {
        // A verification resend belongs to the session created at registration.
        // Authenticating it prevents address enumeration and lets the API report
        // real delivery failure instead of returning a misleading generic success.
        Route::post('resend-otp', [AuthController::class, 'resendOtp'])
            ->middleware('throttle:auth-otp');
        Route::get('me', [AuthController::class, 'me']);
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('sessions', [AuthController::class, 'sessions']);
        Route::delete('sessions/{tokenId}', [AuthController::class, 'revokeSession']);
        Route::post('logout-other-sessions', [AuthController::class, 'logoutOtherSessions']);
        Route::post('change-password', [AuthController::class, 'changePassword']);
        Route::post('change-email', [AuthController::class, 'changeEmail']);
        Route::put('profile', [AuthController::class, 'updateProfile']);
        Route::post('avatar', [AuthController::class, 'uploadAvatar']);
        Route::delete('avatar', [AuthController::class, 'deleteAvatar']);
    });
});

Route::prefix('external')->group(function () {
    // Code→token exchange is the brute-forceable surface: throttle hard.
    // README §6.5: 6/min — named limiter `external-resolve`.
    Route::post('resolve-code', [ExternalDoctorController::class, 'resolveCode'])
        ->middleware('throttle:external-resolve');
    // Same payload-free cursor used by signed-in clients, scoped to this
    // access token so the guest portal remains live even without WebSockets.
    Route::get('{token}/pulse', ExternalRealtimePulseController::class)
        ->middleware('throttle:external-pulse');
    // Writes via a leaked link — scope 30/min per token, not per IP.
    Route::middleware('throttle:external-write')->group(function () {
        Route::post('{token}/broadcasting/auth', ExternalBroadcastAuthController::class);
        Route::get('{token}', [ExternalDoctorController::class, 'show']);
        Route::post('{token}/notes', [ExternalDoctorController::class, 'addNote']);
        Route::post('{token}/vitals', [ExternalDoctorController::class, 'addVital']);
        Route::post('{token}/medications', [ExternalDoctorController::class, 'addMedication']);
        Route::post('{token}/documents', [ExternalDoctorController::class, 'uploadDocument']);
    });
});

// README §6.5: general authenticated API — 120/min/user (named `api-general`).
Route::middleware(['auth:sanctum', 'account.active', 'email.verified', 'throttle:api-general'])->group(function () {
    Route::post('fcm-tokens', [FcmTokenController::class, 'store']);
    Route::delete('fcm-tokens', [FcmTokenController::class, 'destroy']);

    // Per-user preferences — any authenticated role.
    Route::get('me/settings', [UserSettingsController::class, 'show']);
    Route::patch('me/settings', [UserSettingsController::class, 'update']);

    // Durable personal inbox — shared by patients, doctors and operations
    // staff. Ownership is enforced inside NotificationsController.
    Route::get('me/notifications', [NotificationsController::class, 'index']);
    Route::patch('me/notifications/{notification}/read', [NotificationsController::class, 'markRead']);
    Route::patch('me/notifications/{notification}/resolve', [NotificationsController::class, 'resolve']);
    Route::post('me/notifications/read-all', [NotificationsController::class, 'markAllRead']);

    // Read/resolve state for client-computed staff notifications.
    Route::get('me/notification-states', [StaffNotificationStateController::class, 'index']);
    Route::post('me/notification-states', [StaffNotificationStateController::class, 'upsert']);
    Route::post('me/notification-states/read-all', [StaffNotificationStateController::class, 'readAll']);
});

// README §7.1 — the change cursor every signed-in client polls when it has no
// live socket. Its own limiter: this is answered every few seconds and must
// not eat the general API budget it exists to save.
Route::middleware(['auth:sanctum', 'account.active', 'email.verified', 'throttle:realtime-pulse'])
    ->get('me/pulse', RealtimePulseController::class);

Route::middleware(['auth:sanctum', 'account.active', 'email.verified', 'throttle:api-general', 'role:patient'])->prefix('patient')->group(function () {
    Route::get('session', [PatientSessionController::class, 'show']);

    // The patient's own record in the shape their clinic reads it — the same
    // dossier an admin or doctor opens, served to its subject.
    Route::get('record', [PatientRecordController::class, 'show']);
    Route::post('record/report-requests', [PatientRecordController::class, 'requestReport']);

    Route::get('profile', [PatientProfileController::class, 'show']);
    Route::put('profile/account', [PatientProfileController::class, 'updateAccount']);
    Route::put('profile/health', [PatientProfileController::class, 'updateHealth']);
    Route::post('onboarding', [PatientProfileController::class, 'completeOnboarding']);
    Route::post('emergency-contacts', [PatientProfileController::class, 'storeEmergencyContact']);
    Route::delete('emergency-contacts/{contact}', [PatientProfileController::class, 'destroyEmergencyContact']);

    Route::get('vitals', [VitalsController::class, 'index']);
    Route::post('vitals', [VitalsController::class, 'store']);
    Route::patch('tracked-vitals', [PatientTrackedVitalsController::class, 'update']);

    Route::post('medications', [MedicationsController::class, 'store']);
    Route::patch('medications/{medication}', [MedicationsController::class, 'update']);
    Route::delete('medications/{medication}', [MedicationsController::class, 'destroy']);
    Route::patch('medication-doses/{dose}', [MedicationsController::class, 'recordDose']);

    // Nutrition the patient plans for themselves, plus the progress log the
    // care team reads back. Adherence can be recorded against a clinician's
    // plan; only self-authored meals can be edited or removed here.
    Route::post('meal-plans', [PatientMealPlansController::class, 'store']);
    Route::patch('meal-plans/{mealPlan}', [PatientMealPlansController::class, 'update']);
    Route::delete('meal-plans/{mealPlan}', [PatientMealPlansController::class, 'destroy']);
    Route::post('meal-plans/{mealPlan}/log', [PatientMealPlansController::class, 'log']);

    Route::post('appointments', [AppointmentsController::class, 'store']);
    Route::patch('appointments/{appointment}', [AppointmentsController::class, 'update']);
    Route::delete('appointments/{appointment}', [AppointmentsController::class, 'destroy']);

    Route::get('documents', [DocumentsController::class, 'index']);
    Route::post('documents', [DocumentsController::class, 'store']);
    Route::patch('documents/{document}', [DocumentsController::class, 'update']);
    Route::delete('documents/{document}', [DocumentsController::class, 'destroy']);
    // The patient's route to having a clinician-filed document taken out. It
    // is the only thing that authorises a staff-side delete.
    Route::post('documents/{document}/request-removal', [DocumentsController::class, 'requestRemoval']);
    Route::delete('documents/{document}/request-removal', [DocumentsController::class, 'cancelRemoval']);
    Route::get('documents/{document}/stream', [DocumentsController::class, 'stream']);
    Route::get('documents/{document}/download', [DocumentsController::class, 'downloadUrl']);

    Route::get('conversations/{conversation}/messages', [MessagesController::class, 'thread']);
    Route::post('conversations/{conversation}/messages', [MessagesController::class, 'send']);
    Route::post('conversations/{conversation}/read', [MessagesController::class, 'markRead']);

    Route::get('notifications', [NotificationsController::class, 'index']);
    Route::patch('notifications/{notification}/read', [NotificationsController::class, 'markRead']);
    Route::patch('notifications/{notification}/resolve', [NotificationsController::class, 'resolve']);
    Route::post('notifications/read-all', [NotificationsController::class, 'markAllRead']);

    Route::post('support-tickets', [SupportController::class, 'store']);
    Route::post('support-tickets/{ticket}/replies', [SupportController::class, 'reply']);
    Route::patch('support-tickets/{ticket}/close', [SupportController::class, 'close']);

    Route::post('sos', [SosController::class, 'trigger']);
    Route::patch('sos/{event}', [SosController::class, 'resolve']);

    Route::get('care/providers', [CareController::class, 'providers']);
    Route::post('care/requests', [CareController::class, 'requestProvider']);
    Route::patch('care/requests/{careRequest}', [CareController::class, 'cancelRequest']);

    // Documents the patient is asking the care team — or one named doctor —
    // to produce. The other direction of the upload path.
    Route::get('document-requests', [DocumentRequestsController::class, 'index']);
    Route::post('document-requests', [DocumentRequestsController::class, 'store']);
    Route::delete('document-requests/{documentRequest}', [DocumentRequestsController::class, 'cancel']);

    Route::get('vital-report-requests', [VitalReportRequestsController::class, 'index']);
    Route::post('vital-report-requests', [VitalReportRequestsController::class, 'store']);
    Route::patch('vital-report-requests/{vitalReportRequest}', [VitalReportRequestsController::class, 'cancel']);

    // Reports drawn from this patient's record. Read-only: a doctor's
    // signature authorises a report now, so there is nothing here to approve.
    Route::get('report-consents', [PatientReportConsentsController::class, 'index']);
    // The issued report itself, for the patient to read, print or save as PDF.
    Route::get('report-consents/{reportRequest}/document', [PatientReportConsentsController::class, 'document']);

    // Patient-managed external access links/codes (emergency consults).
    Route::get('external-access', [PatientExternalAccessController::class, 'index']);
    Route::post('external-access', [PatientExternalAccessController::class, 'store']);
    Route::patch('external-access/{externalToken}/revoke', [PatientExternalAccessController::class, 'revoke']);

});

Route::middleware(['auth:sanctum', 'account.active', 'email.verified', 'throttle:api-general', 'role:doctor'])->prefix('doctor')->group(function () {
    Route::get('session', [DoctorSessionController::class, 'show']);

    Route::get('patients/{patient}', [DoctorPatientController::class, 'show']);
    // The windowed clinical chart — same payload a coordinator gets, scoped
    // to this doctor's caseload.
    Route::get('patients/{patient}/chart', [PatientChartController::class, 'show']);
    Route::post('patients/{patient}/notes', [PatientChartController::class, 'storeNote']);
    Route::patch('patients/{patient}/chart', [DoctorPatientController::class, 'updateChart']);
    Route::patch('patients/{patient}/assigned-vitals', [DoctorPatientController::class, 'updateAssignedVitals']);
    // Staff-assisted entry: a reading taken at the desk or read back by phone.
    Route::post('patients/{patient}/vitals', [DoctorPatientController::class, 'storeVital']);
    // A patient's documents, as their care team sees them. The dossier carries
    // these too, but a doctor watching a patient upload the result they were
    // asked for needs the list on its own — reloading the whole chart to find
    // out whether one file arrived is not a refresh anyone will do.
    Route::get('patients/{patient}/documents', [DoctorPatientController::class, 'indexDocuments']);
    Route::post('patients/{patient}/documents', [DoctorPatientController::class, 'storeDocument']);
    Route::patch('patients/{patient}/documents/{document}', [DoctorPatientController::class, 'updateDocument']);
    Route::delete('patients/{patient}/documents/{document}', [DoctorPatientController::class, 'honourDocumentRemoval']);
    Route::post('patients/{patient}/documents/{document}/decline-removal', [DoctorPatientController::class, 'declineDocumentRemoval']);
    Route::get('patients/{patient}/documents/{document}/stream', [DoctorPatientController::class, 'streamDocument']);
    Route::get('patients/{patient}/documents/{document}/download', [DoctorPatientController::class, 'downloadDocument']);

    Route::get('alerts', [DoctorAlertsController::class, 'index']);
    Route::patch('alerts/{alert}/acknowledge', [DoctorAlertsController::class, 'acknowledge']);
    Route::patch('alerts/{alert}/resolve', [DoctorAlertsController::class, 'resolve']);

    Route::post('prescriptions', [DoctorPrescriptionsController::class, 'store']);
    Route::patch('prescriptions/{medication}/revoke', [DoctorPrescriptionsController::class, 'revoke']);

    Route::get('reports', [DoctorReportsController::class, 'index']);
    Route::post('reports', [DoctorReportsController::class, 'store']);
    Route::patch('reports/{report}', [DoctorReportsController::class, 'update']);
    Route::patch('reports/{report}/publish', [DoctorReportsController::class, 'publish']);
    Route::delete('reports/{report}', [DoctorReportsController::class, 'destroy']);

    Route::get('appointments', [DoctorAppointmentsController::class, 'index']);
    Route::post('appointments', [DoctorAppointmentsController::class, 'store']);
    Route::patch('appointments/{appointment}', [DoctorAppointmentsController::class, 'update']);

    Route::get('vital-catalog', [DoctorVitalCatalogController::class, 'index']);
    Route::post('vital-catalog', [DoctorVitalCatalogController::class, 'store']);
    Route::patch('vital-catalog/{vitalCatalog}', [DoctorVitalCatalogController::class, 'update']);
    Route::delete('vital-catalog/{vitalCatalog}', [DoctorVitalCatalogController::class, 'destroy']);

    Route::post('meal-plans', [DoctorMealPlansController::class, 'store']);
    Route::delete('meal-plans/{mealPlan}', [DoctorMealPlansController::class, 'destroy']);

    // The shared care-team queue. Every doctor on the caseload sees every
    // request; claiming is what makes one of them its owner, and only the
    // owner can complete it.
    Route::get('vital-report-requests', [DoctorVitalReportRequestsController::class, 'index']);
    Route::patch('vital-report-requests/{vitalReportRequest}/claim', [DoctorVitalReportRequestsController::class, 'claim']);
    Route::patch('vital-report-requests/{vitalReportRequest}/release', [DoctorVitalReportRequestsController::class, 'release']);
    Route::patch('vital-report-requests/{vitalReportRequest}/fulfill', [DoctorVitalReportRequestsController::class, 'fulfill']);
    Route::patch('vital-report-requests/{vitalReportRequest}/escalate', [DoctorVitalReportRequestsController::class, 'escalate']);

    Route::get('document-requests', [DoctorDocumentRequestsController::class, 'index']);
    Route::patch('document-requests/{documentRequest}/claim', [DoctorDocumentRequestsController::class, 'claim']);
    Route::patch('document-requests/{documentRequest}/release', [DoctorDocumentRequestsController::class, 'release']);
    // The upload and the close-out are one call; see the controller.
    Route::post('document-requests/{documentRequest}/fulfill', [DoctorDocumentRequestsController::class, 'fulfill']);
    Route::patch('document-requests/{documentRequest}/decline', [DoctorDocumentRequestsController::class, 'decline']);

    // Sign-off on customised patient reports the doctor was nominated for.
    Route::get('report-requests', [DoctorReportSignaturesController::class, 'index']);
    Route::get('report-requests/{reportRequest}', [DoctorReportSignaturesController::class, 'preview']);
    // The report as a page to open and print — a signature needs a proper read,
    // not a glance at a summary in a sheet.
    Route::get('report-requests/{reportRequest}/document', [DoctorReportSignaturesController::class, 'document']);
    Route::post('report-requests/{reportRequest}/sign', [DoctorReportSignaturesController::class, 'sign']);
    Route::post('report-requests/{reportRequest}/decline', [DoctorReportSignaturesController::class, 'decline']);

    // Care-request triage is an admin / mCare-assistant responsibility. A
    // doctor sees the care team they were assigned to, never the accept or
    // decline decision — see DoctorCareRequestDecisionTest.

    // The doctor's own emergencies, live or closed — `?status=all` is what
    // lets a closed case still be followed up.
    Route::get('sos', [DoctorSosController::class, 'index']);
    Route::patch('sos/{event}', [DoctorSosController::class, 'resolve']);

    // How the emergency was worked, not just who ended it.
    Route::get('sos/{event}/actions', [SosResponseActionsController::class, 'index']);
    Route::post('sos/{event}/actions', [SosResponseActionsController::class, 'store']);

    Route::get('conversations', [DoctorMessagesController::class, 'index']);
    Route::get('conversations/{conversation}/messages', [DoctorMessagesController::class, 'thread']);
    Route::post('conversations/{conversation}/messages', [DoctorMessagesController::class, 'send']);
    Route::post('conversations/{conversation}/read', [DoctorMessagesController::class, 'markRead']);
});

Route::middleware(['auth:sanctum', 'account.active', 'email.verified', 'throttle:api-general', 'role:admin,mcare_assistant'])->prefix('admin')->group(function () {
    Route::get('session', [AdminSessionController::class, 'show']);

    // System-wide vital alerts
    Route::get('alerts', [AdminAlertsController::class, 'index']);
    Route::patch('alerts/{alert}/acknowledge', [AdminAlertsController::class, 'acknowledge']);
    Route::patch('alerts/{alert}/resolve', [AdminAlertsController::class, 'resolve']);

    // SOS — existing
    Route::get('sos-events', [AdminSosController::class, 'index'])
        ->middleware('permission:can_access_emergency_location');
    Route::patch('sos-events/{event}', [AdminSosController::class, 'resolve'])
        ->middleware('permission:can_access_emergency_location');
    // The response trail. Same emergency-location grant: the steps name a
    // patient's whereabouts and who went to them.
    Route::get('sos-events/{event}/actions', [SosResponseActionsController::class, 'index'])
        ->middleware('permission:can_access_emergency_location');
    Route::post('sos-events/{event}/actions', [SosResponseActionsController::class, 'store'])
        ->middleware('permission:can_access_emergency_location');
    // Care team first, then anyone else who could take the handover.
    Route::get('sos-events/{event}/candidates', [SosAssignmentCandidatesController::class, 'index'])
        ->middleware('permission:can_access_emergency_location');
    // The handover itself. Both grants apply: this reaches into an emergency
    // *and* binds a patient to a provider, so neither permission alone is
    // enough. Kept off /admin/assignments because a handover is idempotent —
    // the care team is the first place it should go, and they are already
    // assigned by definition.
    Route::post('sos-events/{event}/handover', [SosHandoverController::class, 'store'])
        ->middleware(['permission:can_access_emergency_location', 'permission:can_assign_patients']);

    // Approvals
    Route::get('approvals', [AdminApprovalsController::class, 'index'])
        ->middleware('permission:can_approve_healthworkers');
    Route::patch('approvals/{user}/approve', [AdminApprovalsController::class, 'approve'])
        ->middleware('permission:can_approve_healthworkers');
    Route::patch('approvals/{user}/reject', [AdminApprovalsController::class, 'reject'])
        ->middleware('permission:can_approve_healthworkers');
    Route::post('approvals/{user}/request-info', [AdminApprovalsController::class, 'requestInfo'])
        ->middleware('permission:can_approve_healthworkers');
    Route::post('approvals/{user}/credential', [AdminApprovalsController::class, 'uploadCredential'])
        ->middleware('permission:can_approve_healthworkers');
    Route::get('approvals/{user}/credential/stream', [AdminApprovalsController::class, 'streamCredential'])
        ->middleware('permission:can_approve_healthworkers');

    // Care requests
    Route::get('care-requests', [AdminCareRequestsController::class, 'index'])
        ->middleware('permission:can_manage_care_requests');
    Route::patch('care-requests/{careRequest}/route', [AdminCareRequestsController::class, 'route'])
        ->middleware('permission:can_manage_care_requests');
    Route::patch('care-requests/{careRequest}/cancel', [AdminCareRequestsController::class, 'cancel'])
        ->middleware('permission:can_manage_care_requests');

    // Assignments
    Route::get('assignments', [AdminAssignmentsController::class, 'index'])
        ->middleware('permission:can_assign_patients');
    Route::post('assignments', [AdminAssignmentsController::class, 'store'])
        ->middleware('permission:can_assign_patients');
    Route::delete('assignments/{assignment}', [AdminAssignmentsController::class, 'destroy'])
        ->middleware('permission:can_assign_patients');

    // Patient clinical profile (read-only) + assist-only mutations
    Route::get('patients/{patient}', [AdminPatientsController::class, 'show'])
        ->middleware('permission:can_create_users');
    // The same clinical chart the doctor reads, for the coordinator working
    // an emergency. Gated exactly as the profile read above.
    Route::get('patients/{patient}/chart', [PatientChartController::class, 'show'])
        ->middleware('permission:can_create_users');
    Route::post('patients/{patient}/notes', [PatientChartController::class, 'storeNote'])
        ->middleware('permission:can_create_users');
    Route::patch('patients/{patient}/assigned-vitals',
        [AdminPatientsController::class, 'updateAssignedVitals'])
        ->middleware('permission:can_create_users');

    Route::post('patients/{patient}/vitals', [AdminPatientsController::class, 'storeVital'])
        ->middleware('permission:can_create_users');

    // The vital report queue, at the tiers it escalates to. Escalation has
    // always moved a stale request doctor -> assistant -> admin; until now it
    // moved it to people with no route to act on it, so the patient waited on
    // a report nobody could produce.
    Route::get('vital-report-requests', [AdminVitalReportRequestsController::class, 'index'])
        ->middleware('permission:can_create_users');
    Route::patch('vital-report-requests/{vitalReportRequest}/claim', [AdminVitalReportRequestsController::class, 'claim'])
        ->middleware('permission:can_create_users');
    Route::patch('vital-report-requests/{vitalReportRequest}/release', [AdminVitalReportRequestsController::class, 'release'])
        ->middleware('permission:can_create_users');
    Route::patch('vital-report-requests/{vitalReportRequest}/fulfill', [AdminVitalReportRequestsController::class, 'fulfill'])
        ->middleware('permission:can_create_users');

    // Documents admin staff file into a patient's record. Same store, same
    // patient-side list and viewer as a doctor upload; only the actor differs.
    Route::get('patients/{patient}/documents', [AdminPatientDocumentsController::class, 'indexDocuments'])
        ->middleware('permission:can_create_users');
    Route::post('patients/{patient}/documents', [AdminPatientDocumentsController::class, 'storeDocument'])
        ->middleware('permission:can_create_users');
    Route::patch('patients/{patient}/documents/{document}', [AdminPatientDocumentsController::class, 'updateDocument'])
        ->middleware('permission:can_create_users');
    Route::get('patients/{patient}/documents/{document}/stream', [AdminPatientDocumentsController::class, 'streamDocument'])
        ->middleware('permission:can_create_users');
    Route::get('patients/{patient}/documents/{document}/download', [AdminPatientDocumentsController::class, 'downloadDocument'])
        ->middleware('permission:can_create_users');
    // Answering a removal the patient asked for. Honouring it is the only
    // delete anywhere in the record, and it is unreachable without a standing
    // request from the patient themselves.
    Route::delete('patients/{patient}/documents/{document}', [AdminPatientDocumentsController::class, 'honourDocumentRemoval'])
        ->middleware('permission:can_create_users');
    Route::post('patients/{patient}/documents/{document}/decline-removal', [AdminPatientDocumentsController::class, 'declineDocumentRemoval'])
        ->middleware('permission:can_create_users');

    // Customised patient reports — tick-list, consent, signature, issue.
    Route::get('report-sections', [AdminPatientReportsController::class, 'sections'])
        ->middleware('permission:can_create_users');
    Route::get('report-requests', [AdminPatientReportsController::class, 'index'])
        ->middleware('permission:can_create_users');
    Route::post('patients/{patient}/report-requests', [AdminPatientReportsController::class, 'store'])
        ->middleware('permission:can_create_users');
    Route::get('report-requests/{reportRequest}', [AdminPatientReportsController::class, 'show'])
        ->middleware('permission:can_create_users');
    // Who may be nominated to sign — the patient's care-team doctors.
    Route::get('patients/{patient}/report-signers', [AdminPatientReportsController::class, 'signers'])
        ->middleware('permission:can_create_users');
    Route::post('report-requests/{reportRequest}/issue', [AdminPatientReportsController::class, 'issue'])
        ->middleware('permission:can_create_users');
    // The other three exits from a signed report: back to the doctor for a
    // fix, parked while the admin checks something, or refused outright.
    Route::post('report-requests/{reportRequest}/send-back', [AdminPatientReportsController::class, 'sendBack'])
        ->middleware('permission:can_create_users');
    Route::post('report-requests/{reportRequest}/under-review', [AdminPatientReportsController::class, 'markUnderReview'])
        ->middleware('permission:can_create_users');
    Route::delete('report-requests/{reportRequest}', [AdminPatientReportsController::class, 'reject'])
        ->middleware('permission:can_create_users');
    // The issued report as a file — what staff hand to the recipient.
    Route::get('report-requests/{reportRequest}/document', [AdminPatientReportsController::class, 'document'])
        ->middleware('permission:can_create_users');
    Route::post('report-requests/{reportRequest}/revoke', [AdminPatientReportsController::class, 'revoke'])
        ->middleware('permission:can_create_users');

    // Users
    Route::get('users', [AdminUsersController::class, 'index'])
        ->middleware('permission:can_create_users');
    // Complete dossier for ANY role — patient, doctor, assistant, admin.
    Route::get('users/{user}/profile', [AdminUserProfileController::class, 'show'])
        ->middleware('permission:can_create_users');
    Route::post('users', [AdminUsersController::class, 'store'])
        ->middleware('permission:can_create_users');
    Route::patch('users/{user}/role', [AdminUsersController::class, 'changeRole'])
        ->middleware('permission:can_change_user_types');
    Route::patch('users/{user}/status', [AdminUsersController::class, 'changeStatus'])
        ->middleware('permission:can_create_users');
    Route::post('users/{user}/password-reset', [AdminUsersController::class, 'resetPassword'])
        ->middleware('permission:can_create_users');
    Route::post('users/{user}/unlock', [AdminUsersController::class, 'unlock'])
        ->middleware('permission:can_create_users');
    Route::post('users/{user}/resend-invite', [AdminUsersController::class, 'resendInvite'])
        ->middleware('permission:can_create_users');

    // Permissions (admin only)
    Route::middleware('role:admin')->group(function () {
        Route::get('permissions', [AdminPermissionsController::class, 'index']);
        Route::get('permissions/{user}', [AdminPermissionsController::class, 'show']);
        Route::patch('permissions/{user}', [AdminPermissionsController::class, 'sync']);
    });

    // Announcements
    Route::get('announcements', [AdminAnnouncementsController::class, 'index'])
        ->middleware('permission:can_manage_advertising');
    Route::post('announcements', [AdminAnnouncementsController::class, 'store'])
        ->middleware('permission:can_manage_advertising');
    Route::patch('announcements/{announcement}', [AdminAnnouncementsController::class, 'update'])
        ->middleware('permission:can_manage_advertising');
    Route::patch('announcements/{announcement}/publish', [AdminAnnouncementsController::class, 'publish'])
        ->middleware('permission:can_manage_advertising');
    Route::delete('announcements/{announcement}', [AdminAnnouncementsController::class, 'destroy'])
        ->middleware('permission:can_manage_advertising');

    // Audit log
    Route::get('audit', [AdminAuditController::class, 'index'])
        ->middleware('permission:can_view_activity_logs');
    Route::get('audit/export', [AdminAuditController::class, 'export'])
        ->middleware('permission:can_view_activity_logs');

    // Security incidents
    Route::get('security-incidents', [AdminSecurityIncidentsController::class, 'index'])
        ->middleware('permission:can_view_security_incidents');
    Route::patch('security-incidents/{id}', [AdminSecurityIncidentsController::class, 'resolve'])
        ->middleware('permission:can_view_security_incidents');

    // Support tickets (staff side)
    Route::get('support-tickets', [AdminSupportTicketsController::class, 'index']);
    Route::post('support-tickets/{ticket}/replies', [AdminSupportTicketsController::class, 'reply']);
    Route::patch('support-tickets/{ticket}/assign', [AdminSupportTicketsController::class, 'assign']);
    Route::patch('support-tickets/{ticket}/resolve', [AdminSupportTicketsController::class, 'resolve']);
    Route::patch('support-tickets/{ticket}/close', [AdminSupportTicketsController::class, 'close']);
    Route::patch('support-tickets/{ticket}/reopen', [AdminSupportTicketsController::class, 'reopen']);

    // Conversations
    Route::get('conversations', [AdminConversationsController::class, 'index']);
    Route::post('conversations', [AdminConversationsController::class, 'store']);
    Route::get('conversations/{conversation}/messages', [AdminConversationsController::class, 'thread']);
    Route::post('conversations/{conversation}/messages', [AdminConversationsController::class, 'send']);
    Route::post('conversations/{conversation}/read', [AdminConversationsController::class, 'markRead']);

    // Notifications
    Route::get('notifications', [AdminNotificationsController::class, 'index']);
    Route::patch('notifications/{notification}/read', [AdminNotificationsController::class, 'markRead']);
    Route::patch('notifications/{notification}/resolve', [AdminNotificationsController::class, 'resolve']);
    Route::post('notifications/read-all', [AdminNotificationsController::class, 'markAllRead']);

    // Analytics
    Route::get('analytics/kpis', [AdminAnalyticsController::class, 'kpis'])
        ->middleware('permission:can_view_activity_logs');
    Route::get('analytics/timeseries', [AdminAnalyticsController::class, 'timeseries'])
        ->middleware('permission:can_view_activity_logs');

    // System settings (admin-only)
    Route::middleware('role:admin')->group(function () {
        Route::get('system/settings', [AdminSystemSettingsController::class, 'index']);
        Route::patch('system/settings/{key}', [AdminSystemSettingsController::class, 'update']);
    });

    // Vital catalog (read — admin bypasses; assistant needs can_manage_vital_catalog)
    Route::get('vital-catalog', [AdminVitalCatalogController::class, 'index'])
        ->middleware('permission:can_manage_vital_catalog');
    Route::post('vital-catalog', [AdminVitalCatalogController::class, 'store'])
        ->middleware('permission:can_manage_vital_catalog');
    Route::patch('vital-catalog/{vitalCatalog}', [AdminVitalCatalogController::class, 'update'])
        ->middleware('permission:can_manage_vital_catalog');
    Route::delete('vital-catalog/{vitalCatalog}', [AdminVitalCatalogController::class, 'destroy'])
        ->middleware('permission:can_manage_vital_catalog');
});
