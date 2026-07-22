/// Result of a "Sign in with Apple" popup.
///
/// Apple only returns [firstName]/[lastName]/[email] on the *first* successful
/// authorization for a given app; subsequent logins carry the [idToken] only.
class AppleSignInResult {
  const AppleSignInResult({
    required this.idToken,
    this.email,
    this.firstName,
    this.lastName,
  });

  final String idToken;
  final String? email;
  final String? firstName;
  final String? lastName;
}
