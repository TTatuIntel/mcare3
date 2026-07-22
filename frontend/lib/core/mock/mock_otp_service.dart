/// Mock OTP for password change and security flows (replace with API).
class MockOtpService {
  MockOtpService._();

  static String? _pendingCode;
  static String? _pendingPurpose;

  /// Sends a demo OTP. Returns the code (shown in UI for testing).
  static String send({required String purpose}) {
    _pendingPurpose = purpose;
    _pendingCode = '482901';
    return _pendingCode!;
  }

  static bool verify(String code) =>
      _pendingCode != null && code.trim() == _pendingCode;

  static void clear() {
    _pendingCode = null;
    _pendingPurpose = null;
  }

  static String? get pendingPurpose => _pendingPurpose;
}
