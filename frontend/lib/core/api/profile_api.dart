import 'package:file_picker/file_picker.dart';

import '../../shared/auth/auth_state.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'auth_api.dart';
import 'multipart_file_builder.dart';

/// Authenticated self-service account operations shared by every role:
/// avatar photo, and email change + re-verification.
class ProfileApi {
  ProfileApi._();
  static final ProfileApi instance = ProfileApi._();

  /// Uploads a new profile photo and refreshes the persisted session.
  Future<void> uploadAvatar(PlatformFile file) async {
    if (!AppEnv.backendEnabled) return;
    final multipart = await MultipartFileBuilder.fromPlatformFile(
      file,
      fieldName: 'avatar',
    );
    final res = await ApiClient.instance.postMultipart(
      '/auth/avatar',
      fields: const {},
      files: [multipart],
    );
    await _apply(res);
  }

  Future<void> removeAvatar() async {
    if (!AppEnv.backendEnabled) return;
    final res = await ApiClient.instance.delete('/auth/avatar');
    await _apply(res);
  }

  /// Requests an email change. Confirms the current password server-side and
  /// emails a 6-digit verification code to the new address.
  ///
  /// Deliberately does NOT push the updated (now-unverified) user into
  /// [AuthState] — doing so would trip `RoleGuard`'s email-verified redirect
  /// and tear down the in-progress verification sheet. The session is refreshed
  /// only once the code is confirmed in [verifyEmailCode].
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post(
      '/auth/change-email',
      body: {'current_password': currentPassword, 'new_email': newEmail},
    );
  }

  /// Confirms the emailed code and marks the (new) address verified.
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    if (!AppEnv.backendEnabled) return;
    final data = await AuthApi.instance.verifyOtp(
      identifier: email,
      code: code,
    );
    final userMap = data?['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      await AuthState.instance.applyServerUser(
        userMap,
        token: data?['token'] as String?,
      );
    }
  }

  Future<void> _apply(Map<String, dynamic> res) async {
    final userMap = res['data']?['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      await AuthState.instance.applyServerUser(userMap);
    }
  }
}
