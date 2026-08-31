import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/api/auth_api.dart';
import '../../auth/verify_email_sheet.dart';
import '../../core/auth/apple_sign_in_service.dart';
import '../../core/auth/google_sign_in_service.dart';
import '../../core/env/app_env.dart';
import '../../core/mock/mock_bootstrap.dart';
import '../../core/mock/mock_data.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../state/profile_state.dart';
import '../services/admin_session_service.dart';
import '../state/settings_state.dart';
import '../state/staff_state.dart';
import '../widgets/app_toast.dart';
import 'patient_session_service.dart';
import 'doctor_session_service.dart';
import 'auth_storage.dart';
import '../../core/push/push_notification_service.dart';
import '../../auth/widgets/google_account_picker_sheet.dart';

/// Central auth operations — Laravel Sanctum/OAuth in backend mode and an
/// isolated seeded demonstration flow when backend mode is disabled.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// A social provider whose client ID never reached this build.
  ///
  /// Nothing is broken and retrying cannot help, so the text people see points
  /// them at the way in that does work rather than at a wall. The build-time
  /// cause is the developer's problem, not theirs, so it is appended only in
  /// debug builds — where it names the exact define that is missing, which is
  /// the one thing "not configured for this application build" never said.
  String _unconfigured(String provider, String defineSuffix) {
    const message =
        'is unavailable in this build. Sign in with your email and password '
        'instead.';
    if (!kDebugMode) return '$provider sign-in $message';

    return '$provider sign-in $message\n'
        'Build with --dart-define=MCARE_${defineSuffix}_CLIENT_ID=... '
        '(see frontend/config/app_config.local.json). It must match the API\'s '
        'own client ID or the token it returns is rejected as a mismatch.';
  }

  String get _deviceName {
    if (kIsWeb) return 'mCare Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'mCare Android',
      TargetPlatform.iOS => 'mCare iPhone/iPad',
      TargetPlatform.macOS => 'mCare macOS',
      TargetPlatform.windows => 'mCare Windows',
      TargetPlatform.linux => 'mCare Linux',
      TargetPlatform.fuchsia => 'mCare device',
    };
  }

  /// Human-readable token/session label sent to the backend. Exposed for the
  /// OTP continuation so verification preserves the original device session.
  String get deviceName => _deviceName;

  /// Email/password sign-in (mock or API).
  Future<AuthFlowResult> signInWithPassword({
    required String identifier,
    required String password,
    bool remember = false,
  }) async {
    if (AppEnv.backendEnabled) {
      return _apiPostAuth('/auth/login', {
        'identifier': identifier,
        'password': password,
        'remember': remember,
        'device_name': _deviceName,
      });
    }
    if (!AppEnv.demoDataEnabled) {
      return AuthFlowResult.failed(
        'The mCare API is required. Start the backend or explicitly enable UI fixture mode.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 500));
    final user = _resolveMockUser(identifier);
    if (user.role == UserRole.patient) {
      AuthState.instance.signIn(user, password: password);
      MockBootstrap.seedPatientSession();
      return AuthFlowResult.signedIn(user, seededProfile: true);
    }
    // Staff session — seed the staff store + assistant permissions.
    final grants = user.role == UserRole.mcareAssistant
        // Assistant signs in with the full delegated set so the demo
        // exercises every screen; admins can revoke from the Permissions
        // screen.
        ? AssistantPermissions.all
        : const <String>[];
    AuthState.instance.signIn(
      user,
      password: password,
      assistantPermissions: grants,
    );
    StaffState.instance.seedDemo();
    // Seed the shared patient stores too so messages/notifications/support
    // populate for staff (they read the same unified pipeline).
    MockBootstrap.seedPatientSession();
    return AuthFlowResult.signedIn(user, seededProfile: true);
  }

  /// Maps mock-mode identifiers to one of the seeded users. Defaults to
  /// the patient so existing demos still work.
  AppUser _resolveMockUser(String identifier) {
    final id = identifier.trim().toLowerCase();
    if (id.startsWith('dr.') ||
        id.contains('mensah') ||
        id.contains('doctor')) {
      return MockData.sampleDoctor();
    }
    if (id.startsWith('admin') || id.contains('@mcare.health')) {
      return MockData.sampleAdmin();
    }
    if (id.startsWith('assistant') || id.contains('assistant')) {
      return MockData.sampleAssistant();
    }
    if (id.startsWith('ext') || id.contains('external')) {
      return MockData.sampleExternalDoctor();
    }
    return MockData.samplePatient();
  }

  /// Google OAuth — GSI on web, the official native SDK on Android/iOS, and
  /// mock accounts only when the entire application is in demo mode.
  Future<AuthFlowResult> signInWithGoogle({
    required BuildContext context,
    bool createAccount = false,
    bool remember = false,
  }) async {
    if (GoogleSignInService.instance.isConfigured && AppEnv.backendEnabled) {
      return _googleSignInWithGsi(
        createAccount: createAccount,
        remember: remember,
      );
    }

    if (AppEnv.backendEnabled) {
      return AuthFlowResult.failed(_unconfigured('Google', 'GOOGLE'));
    }
    if (!AppEnv.demoDataEnabled) {
      return AuthFlowResult.failed(
        'Google Sign-In requires the mCare API in this build.',
      );
    }

    final account = await GoogleAccountPickerSheet.show(context);
    if (account == null) return AuthFlowResult.userCancelled;

    if (account.idToken != null &&
        account.idToken!.isNotEmpty &&
        !account.idToken!.startsWith('mock')) {
      return _googleSignInWithToken(
        idToken: account.idToken!,
        email: account.email,
        firstName: account.firstName,
        lastName: account.lastName,
        createAccount: createAccount,
        remember: remember,
      );
    }

    if (AppEnv.backendEnabled) {
      return _apiPostAuth('/auth/google', {
        'id_token': account.idToken ?? 'mock-token-${account.email}',
        'create_account': createAccount,
        'email': account.email,
        'first_name': account.firstName,
        'last_name': account.lastName,
        'remember': remember,
        'device_name': _deviceName,
      });
    }

    await Future.delayed(const Duration(milliseconds: 450));

    if (account.isReturningPatient) {
      final user = MockData.samplePatient();
      AuthState.instance.signIn(user);
      MockBootstrap.seedPatientSession();
      return AuthFlowResult.signedIn(user, seededProfile: true);
    }

    return _localGoogleSession(
      email: account.email,
      firstName: account.firstName,
      lastName: account.lastName,
      createAccount: createAccount,
    );
  }

  /// Primary web flow: Google Identity Services → Laravel `/auth/google`.
  Future<AuthFlowResult> _googleSignInWithGsi({
    required bool createAccount,
    required bool remember,
  }) async {
    try {
      final creds = await GoogleSignInService.instance.requestCredentials(
        createAccount: createAccount,
      );
      if (creds == null) return AuthFlowResult.userCancelled;
      return _googleSignInWithToken(
        idToken: creds.idToken,
        email: creds.email,
        firstName: creds.firstName,
        lastName: creds.lastName,
        createAccount: createAccount,
        remember: remember,
      );
    } on StateError catch (e) {
      return AuthFlowResult.failed(e.message);
    } catch (error) {
      if (kIsWeb) {
        return _googleSignInWithReal(
          createAccount: createAccount,
          remember: remember,
        );
      }
      return AuthFlowResult.failed(ApiErrorMessages.sanitize(error.toString()));
    }
  }

  Future<AuthFlowResult> _googleSignInWithReal({
    required bool createAccount,
    required bool remember,
  }) async {
    try {
      await GoogleSignInService.instance.beginRedirectSignIn(
        createAccount: createAccount,
        remember: remember,
        deviceName: _deviceName,
      );
      return AuthFlowResult.userCancelled;
    } catch (e) {
      return AuthFlowResult.failed(
        e is StateError ? e.message : 'Google sign-in failed. ${e.toString()}',
      );
    }
  }

  /// Restores a persisted session after browser reload (web localStorage).
  Future<String?> tryRestoreSession() async {
    if (!AppEnv.backendEnabled) return null;

    final saved = await AuthStorage.read();
    if (saved == null) return null;

    ApiClient.instance.setToken(saved.token);
    try {
      final res = await ApiClient.instance.get('/auth/me');
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) throw StateError('No session data');

      final userMap = data['user'] as Map<String, dynamic>?;
      if (userMap == null) throw StateError('No user in session');

      final user = AppUser.fromJson(userMap);
      AuthState.instance.signIn(user);
      _applyAssistantPermissions(data);

      final hasProfile = data['has_health_profile'] == true;
      if (user.role == UserRole.patient) {
        if (hasProfile) {
          await PatientSessionService.instance.syncFromApi();
        } else {
          ProfileState.instance.clear(confirmedMissing: true);
        }
      } else {
        await _seedStaffSession(user.role);
      }

      await _syncNotificationDelivery(user);

      return _routeAfterAuth(user, hasProfile);
    } on ApiException catch (e) {
      // Only a rejected token invalidates the saved session. A 5xx or an
      // offline backend must not silently sign out a remembered user — the
      // token is still good and will restore on the next launch.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await AuthStorage.clear();
        ApiClient.instance.setToken(null);
        return null;
      }

      // The API may be briefly offline. Keep a still-unexpired remembered
      // session active from its signed-in cache and retain the token so live
      // services can reconnect without forcing the user through login again.
      try {
        final cachedUser = AppUser.fromJson(saved.user);
        AuthState.instance.signIn(cachedUser);
        return _routeAfterAuth(cachedUser, saved.hasHealthProfile);
      } catch (_) {
        ApiClient.instance.setToken(null);
        return null;
      }
    } catch (_) {
      try {
        final cachedUser = AppUser.fromJson(saved.user);
        AuthState.instance.signIn(cachedUser);
        return _routeAfterAuth(cachedUser, saved.hasHealthProfile);
      } catch (_) {
        ApiClient.instance.setToken(null);
        return null;
      }
    }
  }

  /// Call on web app startup to finish Google OAuth redirect round-trip.
  Future<AuthFlowResult?> tryCompleteGoogleRedirect() async {
    if (!kIsWeb) return null;

    final result = GoogleSignInService.instance.consumeRedirectAuth();
    if (result == null) return null;

    if (!result.isSuccess) {
      return AuthFlowResult.failed(result.error ?? 'Google sign-in failed.');
    }

    return _completeFromOAuthRedirect(result);
  }

  Future<AuthFlowResult> _completeFromOAuthRedirect(
    GoogleRedirectAuthResult result,
  ) async {
    final token = result.token!;
    ApiClient.instance.setToken(token);
    final user = AppUser.fromJson(result.user!);
    AuthState.instance.signIn(user);
    _applyAssistantPermissions(result.user);
    final hasProfile = result.hasHealthProfile;
    if (user.role == UserRole.patient) {
      if (hasProfile) {
        await PatientSessionService.instance.syncFromApi();
      } else {
        ProfileState.instance.clear(confirmedMissing: true);
      }
    } else {
      await _seedStaffSession(user.role);
    }
    await _persistSession(
      token: token,
      user: result.user!,
      hasProfile: hasProfile,
      remember: result.remember,
      expiresAt: result.expiresAt,
    );
    await _syncNotificationDelivery(user);
    return AuthFlowResult.signedIn(user, seededProfile: hasProfile);
  }

  Future<void> _persistSession({
    required String token,
    required Map<String, dynamic> user,
    required bool hasProfile,
    required bool remember,
    DateTime? expiresAt,
  }) async {
    await AuthStorage.save(
      token: token,
      user: user,
      hasHealthProfile: hasProfile,
      remember: remember,
      expiresAt: expiresAt,
    );
  }

  Future<void> _seedStaffSession(UserRole role) async {
    if (role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
      return;
    }
    if (AppEnv.backendEnabled &&
        (role == UserRole.admin || role == UserRole.mcareAssistant)) {
      await _ensureAssistantPermissionsLoaded();
      await AdminSessionService.instance.syncFromApi();
      return;
    }
    StaffState.instance.seedDemo();
    MockBootstrap.seedPatientSession();
  }

  void _applyAssistantPermissions(Map<String, dynamic>? data) {
    if (data == null) return;
    final perms = data['assistant_permissions'] as List?;
    if (perms == null) return;
    AuthState.instance.setAssistantPermissions(perms.map((e) => e.toString()));
  }

  Future<void> _ensureAssistantPermissionsLoaded() async {
    if (!AppEnv.backendEnabled) return;
    final user = AuthState.instance.user;
    if (user?.role != UserRole.mcareAssistant) return;
    try {
      final res = await ApiClient.instance.get('/auth/me');
      final data = res['data'] as Map<String, dynamic>?;
      _applyAssistantPermissions(data);
    } catch (_) {
      // Non-fatal — permission gates fall back to empty set.
    }
  }

  /// Re-pull the signed-in assistant's permission grants from the server.
  ///
  /// Called by the background session poller so that permissions an admin
  /// adds/revokes take effect on the assistant's running session within one
  /// poll cycle — no re-login required. No-op for other roles.
  Future<void> refreshAssistantPermissions() =>
      _ensureAssistantPermissionsLoaded();

  /// Re-reads the signed-in account to see whether it has been verified yet.
  ///
  /// The verification link may be opened anywhere — a desktop mail client, a
  /// different browser — and nothing about that reaches the waiting app. So
  /// the app asks. Without this the person taps the link, sees "verified" in
  /// their browser, and comes back to a popup still demanding a code.
  ///
  /// Returns true once the account is verified, and hydrates the session so
  /// the caller can move straight on.
  Future<bool> refreshVerificationStatus() async {
    if (!AppEnv.backendEnabled) return false;
    try {
      final res = await ApiClient.instance.get('/auth/me');
      final data = res['data'] as Map<String, dynamic>?;
      final userMap = data?['user'] as Map<String, dynamic>?;
      if (userMap == null) return false;

      final user = AppUser.fromJson(userMap);
      if (!user.emailVerified) return false;

      AuthState.instance.signIn(user);
      final hasProfile = data?['has_health_profile'] == true;
      if (user.role == UserRole.patient) {
        if (hasProfile) {
          await PatientSessionService.instance.syncFromApi();
        } else {
          ProfileState.instance.clear(confirmedMissing: true);
        }
      } else {
        await _seedStaffSession(user.role);
      }
      final saved = await AuthStorage.read();
      if (saved != null) {
        await _persistSession(
          token: saved.token,
          user: userMap,
          hasProfile: hasProfile,
          remember: saved.remember,
          expiresAt: saved.expiresAt,
        );
      }
      return true;
    } catch (_) {
      // A poll that cannot reach the server is not an answer. Staying on the
      // code entry is right — it is the route that still works offline-ish.
      return false;
    }
  }

  /// Where a freshly verified user belongs. Exposed so the verification popup
  /// can hand off to the same destination every other sign-in path uses.
  String routeAfterAuth(AppUser user, {bool seededProfile = false}) =>
      _routeAfterAuth(user, seededProfile);

  /// Completes the same secure session hydration after public OTP verification
  /// that password and social sign-in use.
  Future<AuthFlowResult> completeOtpPayload(Map<String, dynamic> data) async {
    final token = data['token'] as String?;
    final userMap = data['user'] as Map<String, dynamic>?;
    if (token == null || userMap == null) {
      return AuthFlowResult.failed('Invalid verification response.');
    }
    ApiClient.instance.setToken(token);
    final user = AppUser.fromJson(userMap);
    AuthState.instance.signIn(user);
    final hasProfile = data['has_health_profile'] == true;
    if (user.role == UserRole.patient) {
      if (hasProfile) {
        await PatientSessionService.instance.syncFromApi();
      } else {
        ProfileState.instance.clear(confirmedMissing: true);
      }
    } else {
      await _seedStaffSession(user.role);
    }
    await _persistSession(
      token: token,
      user: userMap,
      hasProfile: hasProfile,
      remember: data['remember'] == true,
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
    );
    await _syncNotificationDelivery(user);
    return AuthFlowResult.signedIn(user, seededProfile: hasProfile);
  }

  Future<AuthFlowResult> _googleSignInWithToken({
    required String idToken,
    required String email,
    required String firstName,
    required String lastName,
    required bool createAccount,
    required bool remember,
  }) async {
    final body = {
      'id_token': idToken,
      'create_account': createAccount,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'remember': remember,
      'device_name': _deviceName,
    };

    if (AppEnv.backendEnabled) {
      return _apiPostAuth('/auth/google', body);
    }

    try {
      return await _apiPostAuth(
        '/auth/google',
        body,
        allowWhenBackendDisabled: true,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404 && !createAccount) {
        return AuthFlowResult.failed(
          'No mCare account exists for this Google email. Please register first.',
        );
      }
      return AuthFlowResult.failed(e.message);
    } catch (_) {
      return _localGoogleSession(
        email: email,
        firstName: firstName,
        lastName: lastName,
        createAccount: createAccount,
      );
    }
  }

  Future<AuthFlowResult> _appleSignInWithToken({
    required String idToken,
    required String email,
    required String firstName,
    required String lastName,
    required bool createAccount,
    required bool remember,
    required String challengeId,
  }) {
    return _apiPostAuth('/auth/apple', {
      'id_token': idToken,
      'create_account': createAccount,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'remember': remember,
      'device_name': _deviceName,
      'challenge_id': challengeId,
    });
  }

  AuthFlowResult _localGoogleSession({
    required String email,
    required String firstName,
    required String lastName,
    required bool createAccount,
  }) {
    final user = AppUser(
      id: 'u_google_${email.hashCode.abs()}',
      uniqueId:
          'MCR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: '',
      role: UserRole.patient,
    );
    AuthState.instance.signIn(user);
    ProfileState.instance.clear();
    return AuthFlowResult.signedIn(user, seededProfile: false);
  }

  /// Apple Sign-In — AppleID JS on web and Authentication Services on native.
  /// Mock accounts remain available only in explicit demo mode.
  Future<AuthFlowResult> signInWithApple({
    required BuildContext context,
    bool createAccount = false,
    bool remember = false,
  }) async {
    if (AppleSignInService.instance.isConfigured && AppEnv.backendEnabled) {
      try {
        final challenge = await AuthApi.instance.appleChallenge();
        if (challenge.challengeId.isEmpty || challenge.nonce.isEmpty) {
          return AuthFlowResult.failed('Could not start secure Apple sign-in.');
        }
        final creds = await AppleSignInService.instance.requestCredentials(
          nonce: challenge.nonce,
        );
        if (creds == null) return AuthFlowResult.userCancelled;
        return _appleSignInWithToken(
          idToken: creds.idToken,
          email: creds.email ?? '',
          firstName: creds.firstName ?? '',
          lastName: creds.lastName ?? '',
          createAccount: createAccount,
          remember: remember,
          challengeId: challenge.challengeId,
        );
      } on ApiException catch (e) {
        return AuthFlowResult.failed(ApiErrorMessages.sanitize(e.message));
      } catch (e) {
        return AuthFlowResult.failed(ApiErrorMessages.sanitize(e.toString()));
      }
    }

    if (AppEnv.backendEnabled) {
      return AuthFlowResult.failed(_unconfigured('Apple', 'APPLE'));
    }
    if (!AppEnv.demoDataEnabled) {
      return AuthFlowResult.failed(
        'Apple Sign-In requires the mCare API in this build.',
      );
    }

    // Explicit backend-disabled demo mode keeps the existing mock experience.
    await Future.delayed(const Duration(milliseconds: 450));
    if (createAccount) {
      final user = AppUser(
        id: 'u_apple_${DateTime.now().millisecondsSinceEpoch}',
        uniqueId:
            'MCR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        firstName: 'Amara',
        lastName: 'Okonkwo',
        email: 'amara.o@icloud.com',
        phone: '',
        role: UserRole.patient,
      );
      AuthState.instance.signIn(user);
      ProfileState.instance.clear();
      return AuthFlowResult.signedIn(user, seededProfile: false);
    }
    final user = MockData.samplePatient();
    AuthState.instance.signIn(user);
    MockBootstrap.seedPatientSession();
    return AuthFlowResult.signedIn(user, seededProfile: true);
  }

  /// Patient email registration (mock or API).
  Future<AuthFlowResult> registerPatient({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
  }) async {
    if (AppEnv.backendEnabled) {
      return _apiPostAuth('/auth/register', {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': 'patient',
      });
    }
    if (!AppEnv.demoDataEnabled) {
      return AuthFlowResult.failed(
        'Registration requires the mCare API in this build.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 600));
    final user = AppUser(
      id: 'u_new',
      uniqueId:
          'MCR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      role: UserRole.patient,
    );
    AuthState.instance.signIn(user, password: password);
    ProfileState.instance.clear();
    return AuthFlowResult.signedIn(user, seededProfile: false);
  }

  /// Route after auth — used by bootstrap and post-login navigation.
  String routeForAuthUser(AppUser user, bool seededProfile) =>
      _routeAfterAuth(user, seededProfile);

  /// Navigate after a successful auth flow.
  ///
  /// An unverified account is the one case that does not navigate anywhere.
  /// Verification is a short interruption, not a destination: pushing a full
  /// page for it wiped the stack and made a six-digit code look like the next
  /// stage of signing up. It opens over whatever is already on screen, and
  /// this call finishes the journey once the popup closes.
  void completeNavigation(BuildContext context, AuthFlowResult result) {
    if (!result.isSuccess || result.user == null) return;
    final user = result.user!;

    if (!user.emailVerified) {
      unawaited(_verifyThenContinue(context, result));
      return;
    }

    final route = _routeAfterAuth(user, result.seededProfile);
    Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
  }

  Future<void> _verifyThenContinue(
    BuildContext context,
    AuthFlowResult result,
  ) async {
    final outcome = await VerifyEmailSheet.show(
      context,
      dispatch: result.verification,
    );
    if (!context.mounted) return;

    if (outcome != VerificationOutcome.verified) {
      // Nothing was proven, so nothing is unlocked. Landing is where an
      // account that cannot be used yet belongs.
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.landing, (_) => false);
      return;
    }

    // The session was re-hydrated while verifying, so read the user again
    // rather than trusting the unverified copy this call started with.
    final verified = AuthState.instance.user ?? result.user!;
    Navigator.of(context).pushNamedAndRemoveUntil(
      _routeAfterAuth(verified, result.seededProfile),
      (_) => false,
    );
  }

  String _routeAfterAuth(AppUser user, bool seededProfile) {
    if (!user.emailVerified) return RouteNames.verifyEmail;
    switch (user.role) {
      case UserRole.patient:
        if (user.mustChangePassword) return RouteNames.patientForcePassword;
        if (!seededProfile && ProfileState.instance.health == null) {
          return RouteNames.patientOnboarding;
        }
        return RouteNames.patientDashboard;
      case UserRole.doctor:
        if (user.approvalStatus == ApprovalStatus.pendingApproval) {
          return RouteNames.pendingApproval;
        }
        if (!user.isProfileComplete) return RouteNames.doctorCompleteProfile;
        if (user.mustChangePassword) return RouteNames.doctorForcePassword;
        return RouteNames.doctorDashboard;
      case UserRole.admin:
        if (!user.isProfileComplete) return RouteNames.adminCompleteProfile;
        if (user.mustChangePassword) return RouteNames.adminForcePassword;
        return RouteNames.adminDashboard;
      case UserRole.mcareAssistant:
        if (!user.isProfileComplete) return RouteNames.assistantCompleteProfile;
        if (user.mustChangePassword) return RouteNames.assistantForcePassword;
        return RouteNames.assistantDashboard;
      case UserRole.externalDoctor:
        return RouteNames.externalDoctor;
      case UserRole.guest:
        return RouteNames.login;
    }
  }

  Future<AuthFlowResult> _apiPostAuth(
    String path,
    Map<String, dynamic> body, {
    bool allowWhenBackendDisabled = false,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        path,
        body: body,
        allowWhenBackendDisabled:
            allowWhenBackendDisabled || path.startsWith('/auth/'),
      );
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) {
        return AuthFlowResult.failed('Invalid server response.');
      }
      final token = data['token'] as String?;
      if (token != null) ApiClient.instance.setToken(token);
      final userMap = data['user'] as Map<String, dynamic>?;
      if (userMap == null) return AuthFlowResult.failed('No user in response.');
      final user = AppUser.fromJson(userMap);
      AuthState.instance.signIn(user);
      _applyAssistantPermissions(data);
      final hasProfile = data['has_health_profile'] == true;
      final remember = data['remember'] == true || body['remember'] == true;
      final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '');
      if (user.role == UserRole.patient) {
        if (hasProfile) {
          await PatientSessionService.instance.syncFromApi();
        } else {
          ProfileState.instance.clear(confirmedMissing: true);
        }
      } else {
        await _seedStaffSession(user.role);
      }
      if (token != null) {
        await _persistSession(
          token: token,
          user: userMap,
          hasProfile: hasProfile,
          remember: remember,
          expiresAt: expiresAt,
        );
      }
      await _syncNotificationDelivery(user);
      return AuthFlowResult.signedIn(
        user,
        seededProfile: hasProfile,
        noticeMessage: res['message']?.toString(),
        deliveryFailed: data['verification_delivery'] == 'failed',
        verification: data['verification'] is Map<String, dynamic>
            ? VerificationDispatch.fromApi(
                data['verification'] as Map<String, dynamic>,
              )
            : null,
      );
    } on ApiException catch (e) {
      return AuthFlowResult.failed(ApiErrorMessages.sanitize(e.message));
    } catch (e) {
      return AuthFlowResult.failed(ApiErrorMessages.sanitize(e.toString()));
    }
  }

  /// Applies the server preference before requesting OS notification access.
  /// Unverified accounts never register a push token, and a disabled setting
  /// unregisters any existing token instead of merely hiding notifications.
  Future<void> _syncNotificationDelivery(AppUser user) async {
    if (!user.emailVerified) return;
    await SettingsState.instance.pullRemote();
    await PushNotificationService.instance.setEnabled(
      SettingsState.instance.notifications.pushEnabled,
    );
  }
}

class AuthFlowResult {
  const AuthFlowResult._({
    this.user,
    this.seededProfile = false,
    this.errorMessage,
    this.cancelled = false,
    this.noticeMessage,
    this.deliveryFailed = false,
    this.verification,
  });

  final AppUser? user;
  final bool seededProfile;
  final String? errorMessage;
  final bool cancelled;
  final String? noticeMessage;
  final bool deliveryFailed;

  /// Where the verification code was sent, when this flow issued one. Carried
  /// through so the verification popup can name the inbox to look in without
  /// asking the server a second time for what it was just told.
  final VerificationDispatch? verification;

  bool get isSuccess => user != null && errorMessage == null && !cancelled;

  factory AuthFlowResult.signedIn(
    AppUser user, {
    required bool seededProfile,
    String? noticeMessage,
    bool deliveryFailed = false,
    VerificationDispatch? verification,
  }) => AuthFlowResult._(
    user: user,
    seededProfile: seededProfile,
    noticeMessage: noticeMessage,
    deliveryFailed: deliveryFailed,
    verification: verification,
  );

  factory AuthFlowResult.failed(String message) =>
      AuthFlowResult._(errorMessage: message);

  static const userCancelled = AuthFlowResult._(cancelled: true);
}

/// Shared handler for login / register social + password flows.
Future<void> runAuthFlow(
  BuildContext context, {
  required Future<AuthFlowResult> future,
  String? successMessage,
}) async {
  final result = await future;
  if (!context.mounted) return;
  if (result.cancelled) return;
  if (!result.isSuccess) {
    AppToast.error(
      context,
      result.errorMessage ?? 'Sign-in failed. Please try again.',
    );
    return;
  }
  if (successMessage != null) {
    AppToast.success(context, successMessage);
  }
  AuthService.instance.completeNavigation(context, result);
}
