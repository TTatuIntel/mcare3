import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../env/app_env.dart';
import '../env/runtime_config.dart';
import 'google_redirect_auth_result.dart';
import 'google_sign_in_stub.dart'
    if (dart.library.io) 'google_sign_in_native.dart'
    if (dart.library.html) 'google_sign_in_web.dart'
    as platform;

export 'google_redirect_auth_result.dart';

/// Result of a Google Sign-In flow.
class GoogleSignInCredentials {
  const GoogleSignInCredentials({
    required this.idToken,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
  });

  final String idToken;
  final String email;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  static GoogleSignInCredentials fromIdToken(String idToken) {
    final payload = _decodeJwtPayload(idToken);
    return GoogleSignInCredentials(
      idToken: idToken,
      email: payload['email'] as String? ?? '',
      firstName: payload['given_name'] as String? ?? 'Patient',
      lastName: payload['family_name'] as String? ?? '',
      photoUrl: payload['picture'] as String?,
    );
  }

  static Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return {};
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
    } catch (_) {}
    return {};
  }
}

/// Google Sign-In — web uses Google Identity Services and native platforms use
/// the official Google Sign-In SDK. Every ID token is verified by Laravel.
class GoogleSignInService {
  GoogleSignInService._();
  static final GoogleSignInService instance = GoogleSignInService._();

  /// Resolved from the build's dart-define when it has one, otherwise from
  /// the API — see [RuntimeConfig].
  bool get isConfigured => RuntimeConfig.instance.hasGoogleClientId;

  /// Normalise origin (e.g. redirect away from `0.0.0.0`).
  void warmUp() {
    if (!kIsWeb || !isConfigured) return;
    platform.warmUpGoogleSignIn();
  }

  /// Completes sign-in when returning from Google OAuth redirect.
  GoogleRedirectAuthResult? consumeRedirectAuth() {
    if (!kIsWeb) return null;
    return platform.tryConsumeRedirectAuth();
  }

  /// Opens Google's account picker and returns a verified ID token (web GSI).
  Future<GoogleSignInCredentials?> requestCredentials({
    bool selectAccount = true,
    bool createAccount = false,
  }) async {
    if (!isConfigured) return null;
    final token = await platform.promptGoogleIdToken(
      RuntimeConfig.instance.googleClientId,
      selectAccount: selectAccount,
      createAccount: createAccount,
      serverClientId: RuntimeConfig.instance.googleServerClientId,
      iosClientId: AppEnv.configuredGoogleIosClientId,
    );
    if (token == null || token.isEmpty) return null;
    return GoogleSignInCredentials.fromIdToken(token);
  }

  /// Full-page OAuth via Laravel when GSI is unavailable.
  Future<void> beginRedirectSignIn({
    required bool createAccount,
    required bool remember,
    required String deviceName,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Google client ID missing. The API reported none and this build '
        'pinned none via MCARE_GOOGLE_CLIENT_ID.',
      );
    }
    if (!kIsWeb) {
      throw UnsupportedError(
        'Google Sign-In is configured for Flutter web in this build.',
      );
    }
    await platform.beginRedirectSignIn(
      apiBaseUrl: AppEnv.apiBaseUrl,
      createAccount: createAccount,
      remember: remember,
      deviceName: deviceName,
    );
  }

  @Deprecated('Use beginRedirectSignIn on web')
  Future<GoogleSignInCredentials?> signIn({bool selectAccount = true}) async {
    return null;
  }

  Future<void> signOut() async {
    await platform.revokeGoogleSession();
  }
}
