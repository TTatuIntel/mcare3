/// Payload returned after Laravel Google OAuth redirect (web only).
class GoogleRedirectAuthResult {
  const GoogleRedirectAuthResult({
    this.token,
    this.user,
    this.hasHealthProfile = false,
    this.error,
  });

  final String? token;
  final Map<String, dynamic>? user;
  final bool hasHealthProfile;
  final String? error;

  bool get isSuccess => error == null && token != null && user != null;
}
