import '../../shared/models/support_ticket.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class SupportApi {
  SupportApi._();
  static final SupportApi instance = SupportApi._();

  Future<SupportTicket?> open({
    required String subject,
    required String description,
    required TicketCategory category,
    TicketPriority priority = TicketPriority.normal,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/support-tickets',
      body: PatientDomainMapper.supportTicketToApi(
        subject: subject,
        description: description,
        category: category,
        priority: priority,
      ),
    );
    final json = res['data']?['ticket'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.supportTicketFromApi(json);
  }

  Future<TicketReply?> reply(String ticketId, String body) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/support-tickets/$ticketId/replies',
      body: {'body': body},
    );
    final json = res['data']?['reply'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.ticketReplyFromApi(json);
  }

  Future<SupportTicket?> close(String ticketId) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/support-tickets/$ticketId/close',
    );
    final json = res['data']?['ticket'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.supportTicketFromApi(json);
  }
}
