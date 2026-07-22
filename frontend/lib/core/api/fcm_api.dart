import '../env/app_env.dart';
import 'api_client.dart';

class FcmApi {
  FcmApi._();
  static final FcmApi instance = FcmApi._();

  Future<bool> register({
    required String token,
    String? platform,
  }) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.post(
      '/fcm-tokens',
      body: {
        'token': token,
        if (platform != null) 'platform': platform,
      },
    );
    return true;
  }

  Future<bool> unregister(String token) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete(
      '/fcm-tokens',
      body: {'token': token},
    );
    return true;
  }
}
