import 'dart:convert';

import '../../core/web/web_platform.dart' as web_platform;

/// Persists auth token + user snapshot for session restore on web reload.
/// Off-web the platform facade falls back to in-memory storage.
class AuthStorage {
  AuthStorage._();

  static const _keyToken = 'mcare_auth_token';
  static const _keyUser = 'mcare_auth_user';

  static String? _read(String key) => web_platform.localStorageGet(key);

  static void _write(String key, String value) =>
      web_platform.localStorageSet(key, value);

  static void _remove(String key) => web_platform.localStorageRemove(key);

  static Future<void> save({
    required String token,
    required Map<String, dynamic> user,
    bool hasHealthProfile = false,
  }) async {
    _write(_keyToken, token);
    _write(
      _keyUser,
      jsonEncode({'user': user, 'has_health_profile': hasHealthProfile}),
    );
  }

  static Future<
    ({String token, Map<String, dynamic> user, bool hasHealthProfile})?
  >
  read() async {
    final token = _read(_keyToken);
    final raw = _read(_keyUser);
    if (token == null || raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final user = decoded['user'] as Map<String, dynamic>?;
      if (user == null) return null;
      return (
        token: token,
        user: user,
        hasHealthProfile: decoded['has_health_profile'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    _remove(_keyToken);
    _remove(_keyUser);
  }
}
