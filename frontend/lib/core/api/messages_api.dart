import '../../shared/models/message.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class MessagesApi {
  MessagesApi._();
  static final MessagesApi instance = MessagesApi._();

  Future<List<ChatMessage>> loadThread(String conversationId) async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance
        .get('/patient/conversations/$conversationId/messages');
    final list = res['data']?['messages'] as List? ?? [];
    return list
        .map((e) => PatientDomainMapper.messageFromApi(
              e as Map<String, dynamic>,
              currentUserId: null,
            ))
        .toList();
  }

  Future<ChatMessage?> send(String conversationId, String body) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/conversations/$conversationId/messages',
      body: {'body': body},
    );
    final json = res['data']?['message'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.messageFromApi(json);
  }

  Future<bool> markRead(String conversationId) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.post('/patient/conversations/$conversationId/read');
    return true;
  }
}
