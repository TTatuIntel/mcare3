class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.name,
    required this.role,
    this.specialty,
    this.avatarColorSeed = 0,
    this.online = false,
  });

  final String id;
  final String name;
  final String role; // 'doctor', 'patient', 'admin', 'assistant'
  final String? specialty;
  final int avatarColorSeed;
  final bool online;

  String get initials {
    final parts = name.split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.read = false,
  });

  final String id;
  final String conversationId;
  final String senderId; // 'me' or participant id
  final String body;
  final DateTime sentAt;
  final bool read;

  ChatMessage copyWith({bool? read}) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    body: body,
    sentAt: sentAt,
    read: read ?? this.read,
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.participant,
    required this.lastMessage,
    required this.unreadCount,
  });

  final String id;
  final ChatParticipant participant;
  final ChatMessage lastMessage;
  final int unreadCount;
}
