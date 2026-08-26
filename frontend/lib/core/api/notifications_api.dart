import '../../shared/models/notification_item.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class NotificationsApi {
  NotificationsApi._();
  static final NotificationsApi instance = NotificationsApi._();

  Future<List<AppNotification>> list() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/notifications');
    final list = res['data']?['notifications'] as List? ?? [];
    return list
        .map(
          (e) => PatientDomainMapper.notificationFromApi(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<AppNotification?> markRead(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/notifications/$id/read',
    );
    final json = res['data']?['notification'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.notificationFromApi(json);
  }

  Future<AppNotification?> resolve(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/notifications/$id/resolve',
    );
    final json = res['data']?['notification'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.notificationFromApi(json);
  }

  Future<bool> markAllRead() async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.post('/patient/notifications/read-all');
    return true;
  }
}
