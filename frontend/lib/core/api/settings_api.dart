import '../env/app_env.dart';
import 'api_client.dart';

/// Thin client for per-user preferences (`/me/settings`).
///
/// All calls are no-ops when the backend is disabled so the caller can keep a
/// single code path and rely on local storage in demo mode.
class SettingsApi {
  SettingsApi._();
  static final SettingsApi instance = SettingsApi._();

  /// Returns the stored preference payload, or null when none exist / offline.
  Future<Map<String, dynamic>?> fetch() async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get('/me/settings');
    return res['data'] as Map<String, dynamic>?;
  }

  /// Persists a partial preference payload; the server merges it.
  Future<void> save(Map<String, dynamic> payload) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/me/settings', body: payload);
  }
}
