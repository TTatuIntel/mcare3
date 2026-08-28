/// Payload returned after Laravel Google OAuth redirect (web only).
class GoogleRedirectAuthResult {
  const GoogleRedirectAuthResult({
    this.token,
    this.user,
    this.hasHealthProfile = false,
    this.remember = false,
    this.expiresAt,
    this.error,
  });

  final String? token;
  final Map<String, dynamic>? user;
  final bool hasHealthProfile;
  final bool remember;
  final DateTime? expiresAt;
  final String? error;

  bool get isSuccess => error == null && token != null && user != null;
}
