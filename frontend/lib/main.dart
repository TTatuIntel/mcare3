import 'dart:async';

import 'core/web/html_splash_bridge.dart';
import 'shared/bootstrap/boot_splash_gate.dart';
import 'shared/bootstrap/launch_readiness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin/alerts/admin_alerts_view.dart';
import 'admin/analytics/admin_analytics_view.dart';
import 'admin/announcements/admin_announcements_view.dart';
import 'admin/approvals/admin_approvals_view.dart';
import 'admin/reports/admin_reports_view.dart';
import 'admin/assignments/admin_assignments_view.dart';
import 'admin/audit/admin_audit_view.dart';
import 'admin/care_requests/admin_care_requests_view.dart';
import 'shared/navigation/staff_route_config.dart';
import 'shared/navigation/staff_route_factory.dart';
import 'shared/sos/staff_sos_hub_view.dart';
import 'admin/guided_hub/admin_guided_operations_view.dart';
import 'admin/notifications/admin_notifications_view.dart';
import 'admin/patients/admin_patients_view.dart';
import 'admin/permissions/admin_permissions_view.dart';
import 'admin/profile/admin_profile_view.dart';
import 'admin/security/admin_security_view.dart';
import 'admin/settings/admin_settings_view.dart';
import 'admin/system/admin_system_view.dart';
import 'admin/users/admin_users_view.dart';
import 'shared/vitals/vital_catalog_screen.dart';
import 'auth/accept_invite_view.dart';
import 'auth/external_doctor_view.dart';
import 'auth/forgot_password_view.dart';
import 'auth/landing_view.dart';
import 'auth/login_view.dart';
import 'auth/verify_email_sheet.dart';
import 'auth/pending_approval_view.dart';
import 'auth/register_view.dart';
import 'doctors/alerts/doctor_alert_detail_view.dart';
import 'doctors/alerts/doctor_alerts_view.dart';
import 'doctors/appointments/doctor_appointments_view.dart';
import 'doctors/dashboard/doctor_action_inbox_view.dart';
import 'doctors/dashboard/doctor_dashboard_view.dart';
import 'doctors/overview/doctor_overview_view.dart';
import 'doctors/vitals/doctor_vitals_hub_view.dart';
import 'doctors/visits/doctor_visits_view.dart';
import 'doctors/patients/doctor_patient_section.dart';
import 'doctors/patients/doctor_patient_workspace_view.dart';
import 'doctors/patients/doctor_patients_view.dart';
import 'doctors/prescriptions/doctor_prescriptions_view.dart';
import 'doctors/reports/doctor_report_editor_view.dart';
import 'doctors/reports/doctor_reports_view.dart';
import 'doctors/settings/doctor_settings_view.dart';
import 'mcare_assistant/assistant_settings_view.dart';
import 'mcare_assistant/assistant_views.dart';
import 'mcare_assistant/guided_hub/assistant_guided_operations_view.dart';
import 'patients/appointments/appointment_detail_view.dart';
import 'patients/appointments/appointments_view.dart';
import 'patients/care_team/care_team_view.dart';
import 'patients/dashboard/patient_dashboard_view.dart';
import 'patients/documents/documents_view.dart';
import 'patients/hubs/patient_care_hub_view.dart';
import 'patients/hubs/patient_health_hub_view.dart';
import 'patients/hubs/patient_more_hub_view.dart';
import 'patients/medications/medication_detail_view.dart';
import 'patients/medications/medications_view.dart';
import 'patients/meals/meals_view.dart';
import 'patients/onboarding/patient_onboarding_view.dart';
import 'patients/messages/chat_thread_view.dart';
import 'patients/messages/messages_view.dart';
import 'patients/notifications/notifications_view.dart';
import 'patients/profile/profile_view.dart';
import 'patients/record/patient_clinical_profile_view.dart';
import 'patients/settings/settings_view.dart';
import 'patients/sos/sos_view.dart';
import 'patients/support/support_view.dart';
import 'patients/vitals/vital_detail_view.dart';
import 'patients/vitals/vital_history_view.dart';
import 'patients/vitals/vitals_7day_view.dart';
import 'patients/vitals/vitals_view.dart';
import 'core/auth/google_sign_in_service.dart';
import 'core/push/push_notification_service.dart';
import 'core/web/url_strategy.dart';
import 'doctors/dashboard/critical_alert_popup.dart';
import 'shared/auth/auth_state.dart';
import 'shared/services/auth_service.dart';
import 'shared/widgets/loading/loading.dart';
import 'shared/widgets/app_toast.dart';
import 'shared/auth/patient_onboarding_gate.dart';
import 'shared/auth/staff_profile_gate.dart';
import 'shared/profile/complete_staff_profile_view.dart';
import 'shared/profile/force_change_password_view.dart';
import 'shared/auth/role_guard.dart';
import 'shared/auth/session_recovery.dart';
import 'shared/constants/route_names.dart';
import 'shared/models/notifications_filter.dart';
import 'shared/models/user_role.dart';
import 'shared/models/vital.dart';
import 'shared/models/vital_detail_args.dart';
import 'shared/state/settings_state.dart';
import 'shared/navigation/sos_navigation.dart';
import 'shared/staff_hub/staff_hub.dart';
import 'shared/bootstrap/app_bootstrap.dart';
import 'shared/navigation/root_navigator.dart';
import 'l10n/app_localizations.dart';
import 'shared/theme/app_colors.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/app_icons.dart';
import 'core/api/api_client.dart';
import 'core/async/request_cache.dart';
import 'shared/widgets/app_error_fallback.dart';
import 'shared/widgets/app_page_route.dart';
import 'shared/widgets/bubble_background.dart';
import 'shared/widgets/pre_login_top_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A hot restart re-runs main() without reloading the page, so the splash
  // from the previous run is still dismissed. Bring it back before any async
  // work starts — otherwise the restart shows a blank page while Flutter
  // rebuilds its canvas. No-op on a cold start (already visible) and on
  // non-web platforms (BootSplashGate covers those).
  HtmlSplashBridge.show();
  // Flutter's stock error box is an unstyled grey rectangle — full-screen it
  // is indistinguishable from a blank page. Debug keeps the red screen so
  // real failures stay loud during development.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => AppErrorFallback(details: details);
  }
  // Clean path URLs on web so `/reset-password?token=...` deep links resolve.
  configureWebUrlStrategy();
  if (kIsWeb) {
    GoogleSignInService.instance.warmUp();
  }
  await PushNotificationService.instance.init();
  // Role modules register logout cleanup here so shared/auth stays decoupled.
  AuthState.addLogoutCleanup(CriticalAlertPopup.reset);
  AuthState.addLogoutCleanup(RequestCache.instance.clear);
  // A token the API refuses is a session that no longer exists — revoked,
  // expired, or an account disabled while the app was open. Ending it here,
  // once, is what stops the app looking signed in while every screen quietly
  // fails its own request.
  ApiClient.instance.onSessionRejected = SessionRecovery.forceSignOut;
  runApp(const McareApp());
}

class McareApp extends StatefulWidget {
  const McareApp({super.key});

  @override
  State<McareApp> createState() => _McareAppState();
}

class _McareAppState extends State<McareApp> {
  /// Hard ceiling on startup work. Session restore and the Google redirect
  /// probe both touch the network; if either hangs we still want the app on
  /// screen. Whatever the outcome, [SessionRecovery.settleLaunch] has the last
  /// word on where the app lands, so a timeout can no longer leave a restored
  /// session staring at the public landing page.
  static const Duration _bootstrapWatchdog = Duration(seconds: 8);

  /// Absolute last resort: the HTML splash comes down after this no matter
  /// what state bootstrap is in, so the app can never sit behind it forever.
  static const Duration _splashWatchdog = Duration(seconds: 12);

  Timer? _splashGuard;

  @override
  void initState() {
    super.initState();
    _splashGuard = Timer(_splashWatchdog, HtmlSplashBridge.dismiss);
    _runBootstrap();
  }

  @override
  void dispose() {
    _splashGuard?.cancel();
    super.dispose();
  }

  Future<void> _runBootstrap() async {
    // Every exit below — success, early return, throw, or timeout — falls
    // through to the `finally`, which is the only place that settles the route
    // and takes the splash down. Previously a null context, a throw out of
    // session restore, or the watchdog skipped the navigation entirely and
    // left a signed-in user on the marketing landing page.
    String? bootstrapRoute;
    var navigated = false;
    try {
      final result = await AppBootstrap.run().timeout(_bootstrapWatchdog);
      bootstrapRoute = result.initialRoute;
      if (!mounted) return;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      if (kIsWeb) {
        final gr = result.googleAuthResult;
        if (gr != null) {
          if (gr.isSuccess) {
            // Owns the whole journey, verification sheet included.
            AuthService.instance.completeNavigation(ctx, gr);
            navigated = true;
            return;
          } else if (!gr.cancelled) {
            AppToast.error(ctx, gr.errorMessage ?? 'Google sign-in failed.');
          }
        }
      }
    } catch (error, stack) {
      // Startup must never be fatal, and it must never be a dead end either.
      // Session restore signs the user in before it returns a route, so the
      // recovery below still finds a dashboard to land on when the failure
      // happened after that point.
      debugPrint('mCare bootstrap failed, recovering to a safe route: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (!navigated) {
        SessionRecovery.settleLaunch(bootstrapRoute: bootstrapRoute);
      }
      LaunchReadiness.instance.markBootstrapComplete();
      _dismissSplashAfterPaint();
    }
  }

  /// Waits two frames so the first real screen is on the canvas before the
  /// HTML splash is removed — without the wait the handoff shows a blank gap.
  void _dismissSplashAfterPaint() {
    _splashGuard?.cancel();
    _splashGuard = null;
    if (!mounted) {
      HtmlSplashBridge.dismiss();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HtmlSplashBridge.dismiss();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AuthState.instance, SettingsState.instance]),
      builder: (context, _) {
        final accent =
            AuthState.instance.user?.role.accent ?? AppColors.brandIndigo;
        return MaterialApp(
          title: 'mCare',
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [AppRouteTracker()],
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(accent: accent),
          darkTheme: AppTheme.dark(accent: accent),
          themeMode: SettingsState.instance.themeMode,
          locale: SettingsState.instance.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (locale, supported) {
            if (locale == null) return const Locale('en');
            for (final s in supported) {
              if (s.languageCode == locale.languageCode) return s;
            }
            return const Locale('en');
          },
          builder: (context, child) => ColoredBox(
            color: AppPalette.scaffoldBg(context),
            // Surfaces a slim top bar for attended API work so a slow network
            // reads as "working" rather than "frozen".
            // Two layers, two jobs: the bar is ambient feedback for reads,
            // the overlay is the visible "working on it" for user actions.
            // BootSplashGate is outermost of the three so the loading mark
            // covers the app on every start and hot restart, on all platforms.
            child: BootSplashGate(
              child: AppBusyBar(
                child: McareBusyOverlay(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          initialRoute: RouteNames.landing,
          // Produce a single-route stack so home screens never have a "/" route
          // lurking underneath them (Flutter's default splits initialRoute on "/").
          onGenerateInitialRoutes: (route) => [
            _onGenerateRoute(RouteSettings(name: route)),
          ],
          onGenerateRoute: _onGenerateRoute,
        );
      },
    );
  }

  /// The document a notification is pointing at, if it named one.
  ///
  /// Notifications carry a map rather than a bare id because the same payload
  /// also carries the report it came from; older ones carry nothing at all and
  /// still open the list, which is what they always did.
  static String? _documentIdArg(Object? arguments) {
    if (arguments is Map) {
      final id = arguments['document_id'];
      if (id is String && id.isNotEmpty) return id;
      if (id is num) return id.toString();
    }
    return null;
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final rawName = settings.name ?? RouteNames.home;
    // A deep-linked initial route arrives as a full path, e.g.
    // `/reset-password?token=abc&email=x`. Split off the query so the switch
    // matches the bare route, and expose the params to token-based screens.
    final parsedUri = Uri.tryParse(rawName);
    final name = (parsedUri != null && parsedUri.path.isNotEmpty)
        ? parsedUri.path
        : rawName;
    final linkParams = <String, String>{...?parsedUri?.queryParameters};
    Widget page;

    switch (name) {
      // ----- Pre-login --------------------------------------------------
      case RouteNames.home:
      case RouteNames.landing:
        page = const LandingView();
        break;
      case RouteNames.login:
        page = const LoginView();
        break;
      case RouteNames.register:
        page = RegisterView(asSheet: false);
        break;
      case RouteNames.forgotPassword:
        page = const _PasswordRecoveryRouteHost();
        break;
      case RouteNames.resetPassword:
        page = _PasswordRecoveryRouteHost(
          initialReset:
              ResetPasswordArgs.tryParse(settings.arguments) ??
              ResetPasswordArgs.tryParse(linkParams),
        );
        break;
      case RouteNames.verifyEmail:
        // Where the emailed verification link lands. The route survives, but
        // it no longer owns a page: it shows landing with the verification
        // sheet over it, so arriving from an inbox looks like arriving
        // anywhere else in the app.
        page = VerifyEmailRouteHost(
          status: linkParams['status'] ?? Uri.base.queryParameters['status'],
          child: const LandingView(),
        );
        break;
      case RouteNames.pendingApproval:
        page = const PendingApprovalView();
        break;
      case RouteNames.acceptInvite:
        final token =
            (settings.arguments as String?) ??
            linkParams['token'] ??
            Uri.base.queryParameters['token'];
        page = AcceptInviteView(token: token);
        break;
      case RouteNames.externalDoctor:
        // Token can arrive as a navigation argument (in-app) or in the URL
        // query string (emergency link opened in an outside doctor's browser).
        final extToken =
            (settings.arguments as String?) ??
            linkParams['token'] ??
            Uri.base.queryParameters['token'];
        page = ExternalDoctorView(token: extToken);
        break;

      // ----- Patient ----------------------------------------------------
      case RouteNames.patientOnboarding:
        page = const RoleGuard(
          allowed: [UserRole.patient],
          child: PatientOnboardingView(),
        );
        break;
      case RouteNames.patientForcePassword:
        page = const RoleGuard(
          allowed: [UserRole.patient],
          child: ForceChangePasswordView(role: UserRole.patient),
        );
        break;
      case RouteNames.patientDashboard:
        page = const _PatientGuarded(child: PatientDashboardView());
        break;
      // The three hub tabs behind the patient bottom nav. Without these cases
      // every tab but Home fell through to the not-found page — and because
      // the nav switches tabs with pushNamedAndRemoveUntil, it did so with an
      // empty stack behind it, leaving no way back.
      case RouteNames.patientHealth:
        page = const _PatientGuarded(child: PatientHealthHubView());
        break;
      case RouteNames.patientCare:
        page = const _PatientGuarded(child: PatientCareHubView());
        break;
      case RouteNames.patientMore:
        page = const _PatientGuarded(child: PatientMoreHubView());
        break;
      case RouteNames.patientVitals:
        page = const _PatientGuarded(child: VitalsView());
        break;
      case RouteNames.patientVitalDetail:
        final args = VitalDetailArgs.tryParse(settings.arguments);
        page = _PatientGuarded(
          child: VitalDetailView(
            vital: args?.vital ?? VitalKey.heartRate,
            initialRangeDays: args?.rangeDays ?? 21,
          ),
        );
        break;
      case RouteNames.patientVitalHistory:
        final vital =
            VitalDetailArgs.tryParse(settings.arguments)?.vital ??
            settings.arguments as VitalKey? ??
            VitalKey.heartRate;
        page = _PatientGuarded(child: VitalHistoryView(vital: vital));
        break;
      case RouteNames.patientVital7Day:
        page = const _PatientGuarded(child: Vitals7DayView());
        break;
      case RouteNames.patientNotifications:
        final filter = NotificationsFilter.tryParse(settings.arguments);
        page = _PatientGuarded(
          child: NotificationsView(
            initialShowResolved: filter?.showResolved ?? false,
          ),
        );
        break;
      case RouteNames.patientMedications:
        page = const _PatientGuarded(child: MedicationsView());
        break;
      case RouteNames.patientMedicationDetail:
        final medId = settings.arguments as String? ?? '';
        page = _PatientGuarded(
          child: MedicationDetailView(medicationId: medId),
        );
        break;
      case RouteNames.patientAppointments:
        page = const _PatientGuarded(child: AppointmentsView());
        break;
      case RouteNames.patientAppointmentDetail:
        final apptId = settings.arguments as String? ?? '';
        page = _PatientGuarded(
          child: AppointmentDetailView(appointmentId: apptId),
        );
        break;
      case RouteNames.patientDocuments:
        // A "your report is ready" alert names the document it is about. The
        // argument used to be dropped here, so every report notification
        // landed the patient on the top of their documents list to go hunting
        // for the thing they had just been told about.
        page = _PatientGuarded(
          child: DocumentsView(openDocumentId: _documentIdArg(settings.arguments)),
        );
        break;
      case RouteNames.patientMeals:
        page = const _PatientGuarded(child: MealsView());
        break;
      case RouteNames.patientMessages:
        page = const _PatientGuarded(child: MessagesView());
        break;
      case RouteNames.patientChatThread:
        final convId = settings.arguments as String? ?? '';
        page = _PatientGuarded(child: ChatThreadView(conversationId: convId));
        break;
      case RouteNames.patientCareTeam:
        page = const _PatientGuarded(child: CareTeamView());
        break;
      case RouteNames.patientProfile:
        page = const _PatientGuarded(child: ProfileView());
        break;
      case RouteNames.patientClinicalProfile:
        // An int argument opens the record on a specific tab, so a
        // notification about a reading or a document can land on it directly.
        final segment = settings.arguments is int
            ? settings.arguments as int
            : 0;
        page = _PatientGuarded(
          child: PatientClinicalProfileView(initialSegment: segment),
        );
        break;
      case RouteNames.patientSettings:
        page = const _PatientGuarded(child: SettingsView());
        break;
      case RouteNames.patientSupport:
        page = const _PatientGuarded(child: SupportView());
        break;
      case RouteNames.patientTicketDetail:
        final ticketId = settings.arguments as String? ?? '';
        page = _PatientGuarded(child: TicketDetailView(ticketId: ticketId));
        break;
      case RouteNames.patientSos:
        page = const _PatientGuarded(child: SosView());
        break;
      case RouteNames.patientReportConsents:
        // Keep old notifications and bookmarks working, but send patients to
        // the single Documents & reports workspace.
        page = const _PatientGuarded(child: DocumentsView());
        break;

      // ----- Doctor ----------------------------------------------------
      case RouteNames.doctorDashboard:
        page = const _DoctorGuarded(child: DoctorDashboardView());
        break;
      case RouteNames.doctorPatients:
        page = const _DoctorGuarded(child: DoctorPatientsView());
        break;
      case RouteNames.doctorPatientChart:
        final args = settings.arguments;
        var pid = '';
        var section = DoctorPatientSection.overview;
        var openSosRespond = false;
        String? sosEventId;
        if (args is String) {
          pid = args;
        } else if (args is Map) {
          pid = args['patientId'] as String? ?? '';
          final raw = args['section'] as String?;
          if (raw != null) {
            section = DoctorPatientSection.values.firstWhere(
              (e) => e.name == raw,
              orElse: () => DoctorPatientSection.overview,
            );
          }
          openSosRespond = args['sosRespond'] == true;
          sosEventId = args['eventId'] as String?;
        }
        page = _DoctorGuarded(
          child: DoctorPatientWorkspaceView(
            patientId: pid,
            initialSection: section,
            openSosRespond: openSosRespond,
            sosEventId: sosEventId,
          ),
        );
        break;
      case RouteNames.doctorInbox:
        page = const _DoctorGuarded(child: DoctorActionInboxView());
        break;
      case RouteNames.doctorAlerts:
        page = const _DoctorGuarded(child: DoctorAlertsView());
        break;
      case RouteNames.doctorAlertDetail:
        final aid = settings.arguments as String? ?? '';
        page = _DoctorGuarded(child: DoctorAlertDetailView(alertId: aid));
        break;
      case RouteNames.doctorVisits:
        page = const _DoctorGuarded(child: DoctorVisitsView());
        break;
      case RouteNames.doctorOverview:
        page = const _DoctorGuarded(child: DoctorOverviewView());
        break;
      case RouteNames.doctorVitals:
        page = const _DoctorGuarded(child: DoctorVitalsHubView());
        break;
      case RouteNames.doctorVitalTemplate:
        page = const _DoctorGuarded(child: VitalCatalogScreen.doctor());
        break;
      case RouteNames.doctorAppointments:
        page = const _DoctorGuarded(child: DoctorAppointmentsView());
        break;
      case RouteNames.doctorPrescriptions:
        page = const _DoctorGuarded(child: DoctorPrescriptionsView());
        break;
      case RouteNames.doctorReports:
        page = const _DoctorGuarded(child: DoctorReportsView());
        break;
      case RouteNames.doctorReportEditor:
        page = _DoctorGuarded(
          child: DoctorReportEditorView(argument: settings.arguments),
        );
        break;
      case RouteNames.doctorMessages:
        page = _DoctorGuarded(
          child: StaffRouteFactory.messages(
            StaffRouteConfig.doctor(RouteNames.doctorMessages),
          ),
        );
        break;
      case RouteNames.doctorChatThread:
        final cid = settings.arguments as String? ?? '';
        page = _DoctorGuarded(
          child: StaffRouteFactory.chatThread(
            StaffRouteConfig.doctor(RouteNames.doctorMessages),
            cid,
          ),
        );
        break;
      case RouteNames.doctorNotifications:
        page = _DoctorGuarded(
          child: StaffRouteFactory.notifications(
            StaffRouteConfig.doctor(RouteNames.doctorNotifications),
          ),
        );
        break;
      case RouteNames.doctorCompleteProfile:
        page = const RoleGuard(
          allowed: [UserRole.doctor],
          child: CompleteStaffProfileView(role: UserRole.doctor),
        );
        break;
      case RouteNames.doctorForcePassword:
        page = const RoleGuard(
          allowed: [UserRole.doctor],
          child: ForceChangePasswordView(role: UserRole.doctor),
        );
        break;
      case RouteNames.doctorProfile:
        page = _DoctorGuarded(
          child: StaffRouteFactory.profile(
            StaffRouteConfig.doctor(RouteNames.doctorProfile),
          ),
        );
        break;
      case RouteNames.doctorSettings:
        page = const _DoctorGuarded(child: DoctorSettingsView());
        break;
      case RouteNames.doctorSos:
        final sosArgs = SosNavigation.parseArgs(settings.arguments);
        page = _DoctorGuarded(
          child: StaffSosHubView(
            initialPatientId: sosArgs.patientId,
            initialEventId: sosArgs.eventId,
          ),
        );
        break;

      // ----- Admin -----------------------------------------------------
      case RouteNames.adminDashboard:
        page = const _AdminGuarded(child: AdminGuidedOperationsView());
        break;
      case RouteNames.adminWork:
        page = const _AdminGuarded(
          child: AdminGuidedOperationsView(
            initialSection: StaffHubSection.work,
            currentRoute: RouteNames.adminWork,
          ),
        );
        break;
      case RouteNames.adminPeople:
        page = const _AdminGuarded(
          child: AdminGuidedOperationsView(
            initialSection: StaffHubSection.people,
            currentRoute: RouteNames.adminPeople,
          ),
        );
        break;
      case RouteNames.adminMore:
        page = const _AdminGuarded(
          child: AdminGuidedOperationsView(
            initialSection: StaffHubSection.more,
            currentRoute: RouteNames.adminMore,
          ),
        );
        break;
      case RouteNames.adminSos:
        final adminSosArgs = SosNavigation.parseArgs(settings.arguments);
        page = _AdminGuarded(
          child: StaffSosHubView(
            initialPatientId: adminSosArgs.patientId,
            initialEventId: adminSosArgs.eventId,
          ),
        );
        break;
      case RouteNames.adminPatients:
        page = const _AdminGuarded(child: AdminPatientsView());
        break;
      case RouteNames.adminUsers:
        page = const _AdminGuarded(child: AdminUsersView());
        break;
      case RouteNames.adminUserDetail:
        final uid = settings.arguments as String? ?? '';
        page = _AdminGuarded(child: AdminUserDetailView(userId: uid));
        break;
      case RouteNames.adminApprovals:
        page = const _AdminGuarded(child: AdminApprovalsView());
        break;
      case RouteNames.adminReports:
        page = const _AdminGuarded(child: AdminReportsView());
        break;
      case RouteNames.adminCareRequests:
        page = const _AdminGuarded(child: AdminCareRequestsView());
        break;
      case RouteNames.adminAssignments:
        page = const _AdminGuarded(child: AdminAssignmentsView());
        break;
      case RouteNames.adminVitalCatalog:
        page = const _AdminGuarded(child: VitalCatalogScreen.admin());
        break;
      case RouteNames.adminPermissions:
        page = const _AdminGuarded(child: AdminPermissionsView());
        break;
      case RouteNames.adminSupport:
        page = _AdminGuarded(
          child: StaffRouteFactory.support(
            StaffRouteConfig.admin(RouteNames.adminSupport),
          ),
        );
        break;
      case RouteNames.adminAudit:
        page = const _AdminGuarded(child: AdminAuditView());
        break;
      case RouteNames.adminAnnouncements:
        page = const _AdminGuarded(child: AdminAnnouncementsView());
        break;
      case RouteNames.adminSecurity:
        page = const _AdminGuarded(child: AdminSecurityView());
        break;
      case RouteNames.adminAlerts:
        page = _AdminGuarded(
          child: AdminAlertsView(
            initialStatusFilter: settings.arguments as String? ?? 'open',
          ),
        );
        break;
      case RouteNames.adminAnalytics:
        page = const _AdminGuarded(child: AdminAnalyticsView());
        break;
      case RouteNames.adminSystem:
        page = const _AdminGuarded(child: AdminSystemView());
        break;
      case RouteNames.adminSettings:
        page = const _AdminGuarded(child: AdminSettingsView());
        break;
      case RouteNames.adminMessages:
        page = _AdminGuarded(
          child: StaffRouteFactory.messages(
            StaffRouteConfig.admin(RouteNames.adminMessages),
          ),
        );
        break;
      case RouteNames.adminChatThread:
        final cid = settings.arguments as String? ?? '';
        page = _AdminGuarded(
          child: StaffRouteFactory.chatThread(
            StaffRouteConfig.admin(RouteNames.adminMessages),
            cid,
          ),
        );
        break;
      case RouteNames.adminNotifications:
        page = const _AdminGuarded(child: AdminNotificationsView());
        break;
      case RouteNames.adminCompleteProfile:
        page = const RoleGuard(
          allowed: [UserRole.admin],
          child: CompleteStaffProfileView(role: UserRole.admin),
        );
        break;
      case RouteNames.adminForcePassword:
        page = const RoleGuard(
          allowed: [UserRole.admin],
          child: ForceChangePasswordView(role: UserRole.admin),
        );
        break;
      case RouteNames.adminProfile:
        page = const _AdminGuarded(child: AdminProfileView());
        break;

      // ----- mCare Assistant -------------------------------------------
      case RouteNames.assistantDashboard:
        page = const _AssistantGuarded(child: AssistantGuidedOperationsView());
        break;
      case RouteNames.assistantWork:
        page = const _AssistantGuarded(
          child: AssistantGuidedOperationsView(
            initialSection: StaffHubSection.work,
            currentRoute: RouteNames.assistantWork,
          ),
        );
        break;
      case RouteNames.assistantPeople:
        page = const _AssistantGuarded(
          child: AssistantGuidedOperationsView(
            initialSection: StaffHubSection.people,
            currentRoute: RouteNames.assistantPeople,
          ),
        );
        break;
      case RouteNames.assistantMore:
        page = const _AssistantGuarded(
          child: AssistantGuidedOperationsView(
            initialSection: StaffHubSection.more,
            currentRoute: RouteNames.assistantMore,
          ),
        );
        break;
      case RouteNames.assistantApprovals:
        page = const _AssistantGuarded(child: AssistantApprovalsView());
        break;
      case RouteNames.assistantCareRequests:
        page = const _AssistantGuarded(child: AssistantCareRequestsView());
        break;
      case RouteNames.assistantAssignments:
        page = const _AssistantGuarded(child: AssistantAssignmentsView());
        break;
      case RouteNames.assistantPatients:
        page = const _AssistantGuarded(child: AssistantPatientsView());
        break;
      case RouteNames.assistantUsers:
        page = const _AssistantGuarded(child: AssistantUsersView());
        break;
      case RouteNames.assistantUserDetail:
        final asstUid = settings.arguments as String? ?? '';
        page = _AssistantGuarded(
          child: AssistantUserDetailView(userId: asstUid),
        );
        break;
      case RouteNames.assistantSupport:
        page = const _AssistantGuarded(child: AssistantSupportView());
        break;
      case RouteNames.assistantAudit:
        page = const _AssistantGuarded(child: AssistantAuditView());
        break;
      case RouteNames.assistantAnalytics:
        page = const _AssistantGuarded(child: AssistantAnalyticsView());
        break;
      case RouteNames.assistantAnnouncements:
        page = const _AssistantGuarded(child: AssistantAnnouncementsView());
        break;
      case RouteNames.assistantSecurity:
        page = const _AssistantGuarded(child: AssistantSecurityView());
        break;
      case RouteNames.assistantAlerts:
        page = _AssistantGuarded(
          child: AssistantAlertsView(
            initialStatusFilter: settings.arguments as String? ?? 'open',
          ),
        );
        break;
      case RouteNames.assistantMessages:
        page = _AssistantGuarded(
          child: StaffRouteFactory.messages(
            StaffRouteConfig.assistant(RouteNames.assistantMessages),
          ),
        );
        break;
      case RouteNames.assistantChatThread:
        final cid = settings.arguments as String? ?? '';
        page = _AssistantGuarded(
          child: StaffRouteFactory.chatThread(
            StaffRouteConfig.assistant(RouteNames.assistantMessages),
            cid,
          ),
        );
        break;
      case RouteNames.assistantNotifications:
        page = _AssistantGuarded(
          child: StaffRouteFactory.notifications(
            StaffRouteConfig.assistant(RouteNames.assistantNotifications),
          ),
        );
        break;
      case RouteNames.assistantSos:
        final asstSosArgs = SosNavigation.parseArgs(settings.arguments);
        page = _AssistantGuarded(
          child: AssistantSosView(
            initialPatientId: asstSosArgs.patientId,
            initialEventId: asstSosArgs.eventId,
          ),
        );
        break;
      case RouteNames.assistantVitalCatalog:
        page = const _AssistantGuarded(child: AssistantVitalCatalogView());
        break;
      case RouteNames.assistantCompleteProfile:
        page = const RoleGuard(
          allowed: [UserRole.mcareAssistant],
          child: CompleteStaffProfileView(role: UserRole.mcareAssistant),
        );
        break;
      case RouteNames.assistantForcePassword:
        page = const RoleGuard(
          allowed: [UserRole.mcareAssistant],
          child: ForceChangePasswordView(role: UserRole.mcareAssistant),
        );
        break;
      case RouteNames.assistantSettings:
        page = const _AssistantGuarded(child: AssistantSettingsView());
        break;
      case RouteNames.assistantProfile:
        page = _AssistantGuarded(
          child: StaffRouteFactory.profile(
            StaffRouteConfig.assistant(RouteNames.assistantProfile),
          ),
        );
        break;

      default:
        page = const _NotFoundView();
    }

    return AppPageRoute(builder: (_) => page, settings: settings);
  }
}

/// Compatibility/deep-link route that keeps sign-in visible behind the single
/// recovery modal. Closing the modal normalizes the URL back to `/login` so a
/// reset token is not left in browser history longer than necessary.
class _PasswordRecoveryRouteHost extends StatefulWidget {
  const _PasswordRecoveryRouteHost({this.initialReset});

  final ResetPasswordArgs? initialReset;

  @override
  State<_PasswordRecoveryRouteHost> createState() =>
      _PasswordRecoveryRouteHostState();
}

class _PasswordRecoveryRouteHostState
    extends State<_PasswordRecoveryRouteHost> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRecovery());
  }

  Future<void> _openRecovery() async {
    if (_opened || !mounted) return;
    _opened = true;
    await ForgotPasswordView.show(context, initialReset: widget.initialReset);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) => const LoginView();
}

class _PatientGuarded extends StatelessWidget {
  const _PatientGuarded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => RoleGuard(
    allowed: const [UserRole.patient],
    child: PatientOnboardingGate(child: child),
  );
}

class _DoctorGuarded extends StatelessWidget {
  const _DoctorGuarded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => RoleGuard(
    allowed: const [UserRole.doctor],
    child: StaffProfileGate(
      completeProfileRoute: RouteNames.doctorCompleteProfile,
      forcePasswordRoute: RouteNames.doctorForcePassword,
      child: child,
    ),
  );
}

class _AdminGuarded extends StatelessWidget {
  const _AdminGuarded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => RoleGuard(
    allowed: const [UserRole.admin],
    child: StaffProfileGate(
      completeProfileRoute: RouteNames.adminCompleteProfile,
      forcePasswordRoute: RouteNames.adminForcePassword,
      child: child,
    ),
  );
}

class _AssistantGuarded extends StatelessWidget {
  const _AssistantGuarded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => RoleGuard(
    allowed: const [UserRole.mcareAssistant],
    child: StaffProfileGate(
      completeProfileRoute: RouteNames.assistantCompleteProfile,
      forcePasswordRoute: RouteNames.assistantForcePassword,
      child: child,
    ),
  );
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();
  @override
  Widget build(BuildContext context) {
    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        surfaceColor: surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PreLoginTopBar(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.error,
                          size: 48,
                          color: AppPalette.textMuted(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Page not found',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                RouteNames.home,
                                (_) => false,
                              ),
                          child: const Text('Back home'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
