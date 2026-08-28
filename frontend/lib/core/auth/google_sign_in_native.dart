import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_redirect_auth_result.dart';

bool _initialized = false;

void warmUpGoogleSignIn() {}

GoogleRedirectAuthResult? tryConsumeRedirectAuth() => null;

Future<void> ensureGoogleSignInLoaded() async {}

Future<void> beginRedirectSignIn({
  required String apiBaseUrl,
  required bool createAccount,
}) async {
  throw UnsupportedError('Redirect-based Google Sign-In is web-only.');
}

Future<void> _initialize({
  required String clientId,
  required String serverClientId,
  required String iosClientId,
}) async {
  if (_initialized) return;

  final isApplePlatform =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  await GoogleSignIn.instance.initialize(
    clientId: isApplePlatform && iosClientId.isNotEmpty ? iosClientId : null,
    serverClientId: serverClientId.isNotEmpty ? serverClientId : clientId,
  );
  _initialized = true;
}

Future<String?> promptGoogleIdToken(
  String clientId, {
  bool selectAccount = true,
  String serverClientId = '',
  String iosClientId = '',
}) async {
  await _initialize(
    clientId: clientId,
    serverClientId: serverClientId,
    iosClientId: iosClientId,
  );

  final signIn = GoogleSignIn.instance;
  if (!signIn.supportsAuthenticate()) {
    throw UnsupportedError('Interactive Google Sign-In is unavailable.');
  }

  try {
    if (selectAccount) await signIn.signOut();
    final account = await signIn.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (error) {
    if (error.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}

Future<void> revokeGoogleSession() async {
  if (!_initialized) return;
  await GoogleSignIn.instance.signOut();
}
