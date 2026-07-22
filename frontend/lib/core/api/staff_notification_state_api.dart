import '../env/app_env.dart';
import 'api_client.dart';

/// Persisted read/resolve state for client-computed staff notifications
/// (doctor/admin/assistant inbox items that have no backing notification row).
class StaffNotificationStateApi {
  StaffNotificationStateApi._();
  static final StaffNotificationStateApi instance = StaffNotificationStateApi._();

  /// Returns a map of `notification_key -> (read, resolved)`.
  Future<Map<String, ({bool read, bool resolved})>> fetch() async {
    if (!AppEnv.backendEnabled) return const {};
    final res = await ApiClient.instance.get('/me/notification-states');
    final list = res['data']?['states'] as List? ?? const [];
    final out = <String, ({bool read, bool resolved})>{};
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final key = m['key'] as String?;
      if (key == null) continue;
      out[key] = (
        read: m['read'] == true,
        resolved: m['resolved'] == true,
      );
    }
    return out;
  }

  Future<void> setState(
    String key, {
    bool? read,
    bool? resolved,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post('/me/notification-states', body: {
      'key': key,
      if (read != null) 'read': read,
      if (resolved != null) 'resolved': resolved,
    });
  }

  Future<void> readAll(List<String> keys) async {
    if (!AppEnv.backendEnabled || keys.isEmpty) return;
    await ApiClient.instance.post('/me/notification-states/read-all', body: {
      'keys': keys,
    });
  }
}
