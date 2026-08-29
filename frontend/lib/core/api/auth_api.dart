import '../env/app_env.dart';
import 'api_client.dart';

/// Pre-login and account-recovery auth endpoints.
class AuthApi {
  AuthApi._();
  static final AuthApi instance = AuthApi._();

  /// Starts account recovery. [channel] is `email` (reset link) or `sms`
  /// (6-digit code); omit it to let the API infer one from the identifier.
  ///
  /// Returns the requested channel plus a masked version of the submitted
  /// destination. Email recovery accepts an email; SMS recovery accepts a
  /// phone number, preventing the response from exposing account data.
  Future<PasswordResetDispatch> forgotPassword(
    String identifier, {
    String? channel,
  }) async {
    // Mock mode has no gateway to text, so it always reports the email
    // branch — the SMS branch would strand the user on a code screen no
    // code can satisfy.
    if (!AppEnv.backendEnabled) {
      return PasswordResetDispatch(
        channel: 'email',
        destination: identifier,
        expiresInMinutes: 60,
      );
    }
    final res = await ApiClient.instance.post(
      '/auth/forgot-password',
      body: {'identifier': identifier, 'channel': ?channel},
      allowWhenBackendDisabled: true,
    );
    final data = res['data'] as Map<String, dynamic>? ?? const {};
    return PasswordResetDispatch(
      channel: data['channel']?.toString() ?? channel ?? 'email',
      destination: data['destination']?.toString() ?? identifier,
      expiresInMinutes:
          int.tryParse(data['expires_in_minutes']?.toString() ?? '') ?? 60,
    );
  }

  /// Trades an SMS reset code for the email + token the reset screen needs.
  Future<ResetPasswordGrant> verifyResetOtp({
    required String identifier,
    required String code,
  }) async {
    final res = await ApiClient.instance.post(
      '/auth/verify-reset-otp',
      body: {'identifier': identifier, 'code': code},
      allowWhenBackendDisabled: true,
    );
    final data = res['data'] as Map<String, dynamic>? ?? const {};
    return ResetPasswordGrant(
      email: data['email']?.toString() ?? '',
      token: data['token']?.toString() ?? '',
    );
  }

  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post(
      '/auth/reset-password',
      body: {'email': email, 'token': token, 'password': password},
      allowWhenBackendDisabled: true,
    );
  }

  Future<Map<String, dynamic>?> verifyOtp({
    required String identifier,
    required String code,
    String purpose = 'email_verify',
    bool remember = false,
    String? deviceName,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/auth/verify-otp',
      body: {
        'identifier': identifier,
        'code': code,
        'purpose': purpose,
        'remember': remember,
        'device_name': ?deviceName,
      },
      allowWhenBackendDisabled: true,
    );
    return res['data'] as Map<String, dynamic>?;
  }

  Future<void> resendOtp({required String identifier}) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post(
      '/auth/resend-otp',
      body: {'identifier': identifier, 'purpose': 'email_verify'},
      allowWhenBackendDisabled: true,
    );
  }

  Future<List<Map<String, dynamic>>> sessions() async {
    final res = await ApiClient.instance.get('/auth/sessions');
    final data = res['data'] as Map<String, dynamic>?;
    return (data?['sessions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> revokeSession(String id) async {
    await ApiClient.instance.delete('/auth/sessions/$id');
  }

  Future<Map<String, dynamic>?> acceptInvite({
    required String token,
    required String password,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/auth/accept-invite',
      body: {'token': token, 'password': password},
      allowWhenBackendDisabled: true,
    );
    return res['data'] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> externalPortal(String token) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get(
      '/external/$token',
      allowWhenBackendDisabled: true,
    );
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> externalNote(
    String token, {
    required String note,
    String? doctorName,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post(
      '/external/$token/notes',
      body: {
        'note': note,
        if (doctorName != null && doctorName.isNotEmpty)
          'doctor_name': doctorName,
      },
      allowWhenBackendDisabled: true,
    );
  }
}

/// Where a password-reset secret was sent, for UI confirmation copy.
class PasswordResetDispatch {
  const PasswordResetDispatch({
    required this.channel,
    required this.destination,
    required this.expiresInMinutes,
  });

  /// `email` or `sms` — the channel the API actually used.
  final String channel;

  /// Masked address or number, e.g. `j••••e@example.com` / `+234•••••5678`.
  final String destination;
  final int expiresInMinutes;

  bool get isSms => channel == 'sms';
}

/// A verified SMS code, exchanged for the credentials the reset screen posts.
class ResetPasswordGrant {
  const ResetPasswordGrant({required this.email, required this.token});

  final String email;
  final String token;
}
