import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/message.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/state/messages_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatMessage message(String id, int minute) => ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: 'p1',
    body: 'Message $id',
    sentAt: DateTime.utc(2026, 9, 2, 10, minute),
  );

  Conversation conversation(ChatMessage last) => Conversation(
    id: 'c1',
    participant: const ChatParticipant(
      id: 'p1',
      name: 'Patient One',
      role: 'patient',
    ),
    lastMessage: last,
    unreadCount: 1,
  );

  setUp(() {
    AuthState.instance.signIn(
      const AppUser(
        id: 'u1',
        uniqueId: 'MCR-1',
        firstName: 'Test',
        lastName: 'User',
        email: 'test@example.test',
        role: UserRole.patient,
      ),
    );
    ApiClient.instance.setToken('test-token');
    MessagesState.instance.seed(conversations: const [], threads: const {});
  });

  tearDown(() {
    MessagesState.instance.seed(conversations: const [], threads: const {});
    ApiClient.instance.setTransportForTesting(null);
    ApiClient.instance.setToken(null);
    AuthState.instance.signOut();
  });

  test('a live inbox refresh preserves an already loaded thread', () async {
    final first = message('m1', 1);
    final second = message('m2', 2);
    final newest = message('m3', 3);
    MessagesState.instance.seed(
      conversations: [conversation(first)],
      threads: {
        'c1': [first],
      },
    );

    ApiClient.instance.setTransportForTesting(
      MockClient((_) async {
        Map<String, dynamic> json(ChatMessage item) => {
          'id': item.id,
          'conversation_id': item.conversationId,
          'sender_id': item.senderId,
          'body': item.body,
          'sent_at': item.sentAt.toIso8601String(),
          'read': item.read,
        };

        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'messages': [json(first), json(second)],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await MessagesState.instance.loadThread('c1');
    expect(MessagesState.instance.thread('c1'), hasLength(2));

    // Role sessions intentionally contain only the latest preview. A live
    // refresh must append it, not replace the full thread the user is reading.
    MessagesState.instance.seed(
      conversations: [conversation(newest)],
      threads: {
        'c1': [newest],
      },
    );

    expect(MessagesState.instance.thread('c1').map((item) => item.id), [
      'm1',
      'm2',
      'm3',
    ]);
  });
}
