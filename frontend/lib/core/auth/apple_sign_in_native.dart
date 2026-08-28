import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'apple_sign_in_result.dart';

Future<AppleSignInResult?> requestAppleCredentials({
  required String clientId,
  required String redirectUri,
}) async {
  if (!await SignInWithApple.isAvailable()) return null;

  final needsWebAuthentication =
      defaultTargetPlatform == TargetPlatform.android;
  if (needsWebAuthentication && (clientId.isEmpty || redirectUri.isEmpty)) {
    throw StateError(
      'Apple Sign-In on Android requires a Services ID and redirect URI.',
    );
  }

  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: needsWebAuthentication
          ? WebAuthenticationOptions(
              clientId: clientId,
              redirectUri: Uri.parse(redirectUri),
            )
          : null,
    );
    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw StateError('Apple did not return an identity token.');
    }

    return AppleSignInResult(
      idToken: identityToken,
      email: credential.email,
      firstName: credential.givenName,
      lastName: credential.familyName,
    );
  } on SignInWithAppleAuthorizationException catch (error) {
    if (error.code == AuthorizationErrorCode.canceled) return null;
    rethrow;
  }
}
