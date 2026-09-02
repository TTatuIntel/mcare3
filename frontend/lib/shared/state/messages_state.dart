import 'package:flutter/foundation.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/doctor_api.dart';
import '../../core/api/messages_api.dart';
import '../../core/api/patient_domain_mapper.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../models/message.dart';
import '../models/user_role.dart';

class MessagesState extends ChangeNotifier {
  MessagesState._();
  static final MessagesState instance = MessagesState._();

  final List<Conversation> _conversations = [];
  final Map<String, List<ChatMessage>> _threads = {};
  final Set<String> _loadedThreadIds = {};

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  List<ChatMessage> thread(String convId) =>
      List.unmodifiable(_threads[convId] ?? const []);

  Conversation? conversationForPatient({
    required String patientId,
    required String patientName,
  }) {
    final nameKey = patientName.trim().toLowerCase();
    for (final c in _conversations) {
      if (c.participant.id == patientId) return c;
      if (c.participant.role == 'patient' &&
          c.participant.name.trim().toLowerCase() == nameKey) {
        return c;
      }
    }
    return null;
  }

  void seed({
    required List<Conversation> conversations,
    required Map<String, List<ChatMessage>> threads,
  }) {
    _conversations
      ..clear()
      ..addAll(conversations);

    final activeIds = conversations.map((c) => c.id).toSet();
    _threads.removeWhere((id, _) => !activeIds.contains(id));
    _loadedThreadIds.removeWhere((id) => !activeIds.contains(id));

    for (final conversation in conversations) {
      final incoming = threads[conversation.id] ?? const <ChatMessage>[];
      if (!_loadedThreadIds.contains(conversation.id)) {
        _threads[conversation.id] = List<ChatMessage>.from(incoming);
        continue;
      }

      // A role-session payload contains only each conversation's newest
      // message. Preserve a thread the user has already opened and merge that
      // preview into it; clearing the map here used to make the entire chat
      // history disappear whenever a live session refresh arrived.
      final merged = <String, ChatMessage>{
        for (final message in _threads[conversation.id] ?? const [])
          message.id: message,
        for (final message in incoming) message.id: message,
      }.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      _threads[conversation.id] = merged;
    }
    notifyListeners();
  }

  Conversation? byId(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool get _usesStaffInbox {
    final role = AuthState.instance.user?.role;
    return role == UserRole.admin || role == UserRole.mcareAssistant;
  }

  /// Start or reopen a thread with a directory user (admin / assistant).
  Future<String?> startConversationWith({
    required String userId,
    required String name,
    required String role,
    String? specialty,
  }) async {
    final existing = conversationForPatient(
      patientId: userId,
      patientName: name,
    );
    if (existing != null) return existing.id;

    if (!AppEnv.backendEnabled) {
      final id = 'conv_${userId}_${DateTime.now().millisecondsSinceEpoch}';
      final conv = Conversation(
        id: id,
        participant: ChatParticipant(
          id: userId,
          name: name,
          role: role,
          specialty: specialty,
        ),
        lastMessage: ChatMessage(
          id: 'empty_$id',
          conversationId: id,
          senderId: 'me',
          body: '',
          sentAt: DateTime.now(),
          read: true,
        ),
        unreadCount: 0,
      );
      _conversations.insert(0, conv);
      _threads[id] = const [];
      notifyListeners();
      return id;
    }

    final json = await AdminApi.instance.createConversation(userId);
    if (json == null) return null;
    final currentUserId = AuthState.instance.user?.id;
    final conv = PatientDomainMapper.conversationFromApi(
      json,
      currentUserId: currentUserId,
    );
    final i = _conversations.indexWhere((c) => c.id == conv.id);
    if (i == -1) {
      _conversations.insert(0, conv);
    } else {
      _conversations[i] = conv;
    }
    _threads.putIfAbsent(conv.id, () => const []);
    notifyListeners();
    return conv.id;
  }

  /// Optimistic send — returns the local message id.
  Future<String> send(String conversationId, String body) async {
    final id = 'm_${DateTime.now().millisecondsSinceEpoch}';
    final msg = ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: 'me',
      body: body,
      sentAt: DateTime.now(),
      read: true,
    );
    final list = List<ChatMessage>.from(_threads[conversationId] ?? const []);
    list.add(msg);
    _threads[conversationId] = list;
    _bumpPreview(conversationId, msg);
    notifyListeners();

    if (!AppEnv.backendEnabled) return id;

    final role = AuthState.instance.user?.role;
    try {
      if (role == UserRole.doctor) {
        final json = await DoctorApi.instance.sendMessage(conversationId, body);
        if (json != null) {
          final serverMsg = PatientDomainMapper.messageFromApi(json);
          final thread = List<ChatMessage>.from(_threads[conversationId] ?? []);
          final i = thread.indexWhere((m) => m.id == id);
          if (i != -1) thread[i] = serverMsg;
          _threads[conversationId] = thread;
          _bumpPreview(conversationId, serverMsg);
          notifyListeners();
          return serverMsg.id;
        }
      } else if (_usesStaffInbox) {
        final json = await AdminApi.instance.sendMessage(
          conversationId,
          body: body,
        );
        if (json != null) {
          final serverMsg = PatientDomainMapper.messageFromApi(
            json,
            currentUserId: AuthState.instance.user?.id,
          );
          final thread = List<ChatMessage>.from(_threads[conversationId] ?? []);
          final i = thread.indexWhere((m) => m.id == id);
          if (i != -1) thread[i] = serverMsg;
          _threads[conversationId] = thread;
          _bumpPreview(conversationId, serverMsg);
          notifyListeners();
          return serverMsg.id;
        }
      } else {
        final sent = await MessagesApi.instance.send(conversationId, body);
        if (sent == null) throw StateError('send failed');
        return sent.id;
      }
    } catch (_) {
      final thread = List<ChatMessage>.from(_threads[conversationId] ?? []);
      thread.removeWhere((m) => m.id == id);
      _threads[conversationId] = thread;
      notifyListeners();
    }
    return id;
  }

  Future<void> markRead(String conversationId) async {
    final list = _threads[conversationId];
    if (list != null) {
      _threads[conversationId] = list
          .map((m) => m.copyWith(read: true))
          .toList();
    }
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i != -1 && _conversations[i].unreadCount > 0) {
      final c = _conversations[i];
      _conversations[i] = Conversation(
        id: c.id,
        participant: c.participant,
        lastMessage: c.lastMessage,
        unreadCount: 0,
      );
    }
    notifyListeners();

    if (AppEnv.backendEnabled) {
      final role = AuthState.instance.user?.role;
      if (role == UserRole.doctor) {
        await DoctorApi.instance.markConversationRead(conversationId);
      } else if (_usesStaffInbox) {
        await AdminApi.instance.markConversationRead(conversationId);
      } else {
        await MessagesApi.instance.markRead(conversationId);
      }
    }
  }

  Future<void> loadThread(String conversationId) async {
    if (!AppEnv.backendEnabled) return;
    try {
      final role = AuthState.instance.user?.role;
      if (role == UserRole.doctor) {
        final rows = await DoctorApi.instance.loadThread(conversationId);
        _threads[conversationId] = rows
            .map((e) => PatientDomainMapper.messageFromApi(e))
            .toList();
      } else if (_usesStaffInbox) {
        final rows = await AdminApi.instance.threadMessages(conversationId);
        _threads[conversationId] = rows
            .map(
              (e) => PatientDomainMapper.messageFromApi(
                e,
                currentUserId: AuthState.instance.user?.id,
              ),
            )
            .toList();
      } else {
        final msgs = await MessagesApi.instance.loadThread(conversationId);
        _threads[conversationId] = msgs;
      }
      _loadedThreadIds.add(conversationId);
      notifyListeners();
    } catch (_) {
      // Keep optimistic preview thread.
    }
  }

  void _bumpPreview(String convId, ChatMessage msg) {
    final i = _conversations.indexWhere((c) => c.id == convId);
    if (i == -1) return;
    final old = _conversations[i];
    _conversations[i] = Conversation(
      id: old.id,
      participant: old.participant,
      lastMessage: msg,
      unreadCount: msg.senderId == 'me' ? 0 : old.unreadCount + 1,
    );
    _conversations.sort(
      (a, b) => b.lastMessage.sentAt.compareTo(a.lastMessage.sentAt),
    );
  }
}
