import 'google_redirect_auth_result.dart';

/// Non-web stub — Google Sign-In is implemented for Flutter web only.
void warmUpGoogleSignIn() {}

Future<void> ensureGoogleSignInLoaded() async {}

GoogleRedirectAuthResult? tryConsumeRedirectAuth() => null;

Future<void> beginRedirectSignIn({
  required String apiBaseUrl,
  required bool createAccount,
  required bool remember,
  required String deviceName,
}) async {
  throw UnsupportedError('Google Sign-In is only available on Flutter web.');
}

Future<String?> promptGoogleIdToken(
  String clientId, {
  bool selectAccount = true,
  bool createAccount = false,
  String serverClientId = '',
  String iosClientId = '',
}) async {
  throw UnsupportedError('Google Sign-In is unavailable on this platform.');
}

Future<void> revokeGoogleSession() async {}
