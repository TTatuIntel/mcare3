import '../env/app_env.dart';
import '../env/runtime_config.dart';
import 'apple_sign_in_result.dart';
import 'apple_sign_in_stub.dart'
    if (dart.library.io) 'apple_sign_in_native.dart'
    if (dart.library.html) 'apple_sign_in_web.dart'
    as platform;

export 'apple_sign_in_result.dart';

/// Sign in with Apple — web uses AppleID JS and native platforms use Apple's
/// Authentication Services through the official Flutter plugin.
///
/// Gated by [AppEnv.hasAppleClientId]. Production/backend builds fail closed
/// when configuration is absent; only explicit demo mode can use mock users.
class AppleSignInService {
  AppleSignInService._();
  static final AppleSignInService instance = AppleSignInService._();

  bool get isConfigured => RuntimeConfig.instance.hasAppleClientId;

  /// Opens Apple's popup and returns the identity token (+ first-login profile).
  /// Returns null when unconfigured, unsupported, or the user cancels.
  Future<AppleSignInResult?> requestCredentials({required String nonce}) async {
    if (!isConfigured) return null;
    return platform.requestAppleCredentials(
      clientId: RuntimeConfig.instance.appleClientId,
      redirectUri: RuntimeConfig.instance.appleRedirectUri,
      nonce: nonce,
    );
  }
}
