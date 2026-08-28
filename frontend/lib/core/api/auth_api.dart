import '../env/app_env.dart';
import 'api_client.dart';

/// Pre-login and account-recovery auth endpoints.
class AuthApi {
  AuthApi._();
  static final AuthApi instance = AuthApi._();

  Future<void> forgotPassword(String identifier) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post(
      '/auth/forgot-password',
      body: {'identifier': identifier},
      allowWhenBackendDisabled: true,
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
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/auth/verify-otp',
      body: {'identifier': identifier, 'code': code, 'purpose': purpose},
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
