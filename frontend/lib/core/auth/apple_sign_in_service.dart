import 'package:flutter/foundation.dart';

import '../env/app_env.dart';
import 'apple_sign_in_result.dart';
import 'apple_sign_in_stub.dart'
    if (dart.library.html) 'apple_sign_in_web.dart' as platform;

export 'apple_sign_in_result.dart';

/// Sign in with Apple — web uses the AppleID JS SDK popup; other platforms
/// stub out (native would use the `sign_in_with_apple` plugin).
///
/// Gated by [AppEnv.hasAppleClientId]; until `MCARE_APPLE_CLIENT_ID` is set the
/// app falls back to the mock flow in `AuthService.signInWithApple`.
class AppleSignInService {
  AppleSignInService._();
  static final AppleSignInService instance = AppleSignInService._();

  bool get isConfigured => AppEnv.hasAppleClientId;

  /// Opens Apple's popup and returns the identity token (+ first-login profile).
  /// Returns null when unconfigured, off-web, or the user cancels.
  Future<AppleSignInResult?> requestCredentials() async {
    if (!isConfigured || !kIsWeb) return null;
    return platform.requestAppleCredentials(
      clientId: AppEnv.appleClientId,
      redirectUri: AppEnv.appleRedirectUri,
    );
  }
}
