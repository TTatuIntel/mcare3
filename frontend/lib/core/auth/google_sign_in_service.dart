import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../env/app_env.dart';
import 'google_redirect_auth_result.dart';
import 'google_sign_in_stub.dart'
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

/// Google Sign-In — web uses Laravel OAuth redirect; other platforms stub.
class GoogleSignInService {
  GoogleSignInService._();
  static final GoogleSignInService instance = GoogleSignInService._();

  bool get isConfigured => AppEnv.hasGoogleClientId;

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
  }) async {
    if (!isConfigured || !kIsWeb) return null;
    final token = await platform.promptGoogleIdToken(
      AppEnv.googleClientId,
      selectAccount: selectAccount,
    );
    if (token == null || token.isEmpty) return null;
    return GoogleSignInCredentials.fromIdToken(token);
  }

  /// Full-page OAuth via Laravel when GSI is unavailable.
  Future<void> beginRedirectSignIn({required bool createAccount}) async {
    if (!isConfigured) {
      throw StateError(
        'Google client ID missing. Set MCARE_GOOGLE_CLIENT_ID in dart-define.',
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
    );
  }

  @Deprecated('Use beginRedirectSignIn on web')
  Future<GoogleSignInCredentials?> signIn({bool selectAccount = true}) async {
    return null;
  }

  Future<void> signOut() async {
    if (kIsWeb) {
      await platform.revokeGoogleSession();
    }
  }
}
