import 'google_redirect_auth_result.dart';

/// Non-web stub — Google Sign-In is implemented for Flutter web only.
void warmUpGoogleSignIn() {}

Future<void> ensureGoogleSignInLoaded() async {}

GoogleRedirectAuthResult? tryConsumeRedirectAuth() => null;

Future<void> beginRedirectSignIn({
  required String apiBaseUrl,
  required bool createAccount,
}) async {
  throw UnsupportedError('Google Sign-In is only available on Flutter web.');
}

Future<String?> promptGoogleIdToken(
  String clientId, {
  bool selectAccount = true,
}) async {
  throw UnsupportedError('Google Sign-In is only available on Flutter web.');
}

Future<void> revokeGoogleSession() async {}
