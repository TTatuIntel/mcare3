import 'apple_sign_in_result.dart';

/// Non-web stub. Native Apple Sign-In (iOS) would go through the
/// `sign_in_with_apple` plugin; unsupported in this build.
Future<AppleSignInResult?> requestAppleCredentials({
  required String clientId,
  required String redirectUri,
}) async => null;
