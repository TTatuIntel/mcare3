import 'package:flutter/foundation.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/patient_domain_mapper.dart';
import '../../core/api/support_api.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../models/support_ticket.dart';
import '../models/user_role.dart';

class SupportState extends ChangeNotifier {
  SupportState._();
  static final SupportState instance = SupportState._();

  final List<SupportTicket> _tickets = [];

  List<SupportTicket> get all => List.unmodifiable(_tickets);

  List<SupportTicket> get open => _tickets
      .where((t) =>
          t.status == TicketStatus.open ||
          t.status == TicketStatus.inProgress)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<SupportTicket> get closed => _tickets
      .where((t) =>
          t.status == TicketStatus.resolved ||
          t.status == TicketStatus.closed)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void seed(List<SupportTicket> items) {
    _tickets
      ..clear()
      ..addAll(items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  SupportTicket? byId(String id) {
    for (final t in _tickets) {
      if (t.id == id) return t;
    }
    return null;
  }

  String create({
    required String subject,
    required String description,
    required TicketCategory category,
    required TicketPriority priority,
  }) {
    final id = 't_${DateTime.now().millisecondsSinceEpoch}';
    _tickets.insert(
      0,
      SupportTicket(
        id: id,
        subject: subject,
        description: description,
        category: category,
        priority: priority,
        status: TicketStatus.open,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return id;
  }

  void addReply(String ticketId, String body, {bool isStaff = false}) {
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    final t = _tickets[i];
    final reply = TicketReply(
      id: 'tr_${DateTime.now().millisecondsSinceEpoch}',
      author: isStaff ? 'mCare Support' : 'You',
      body: body,
      sentAt: DateTime.now(),
      isStaff: isStaff,
    );
    _tickets[i] = t.copyWith(
      replies: [...t.replies, reply],
      updatedAt: DateTime.now(),
      status: isStaff ? TicketStatus.inProgress : t.status,
    );
    notifyListeners();
  }

  /// Persisting variant of [create]. POSTs to the API and inserts the
  /// server-canonical ticket. Returns the ticket id.
  Future<String> createRemote({
    required String subject,
    required String description,
    required TicketCategory category,
    required TicketPriority priority,
  }) async {
    if (!AppEnv.backendEnabled) {
      return create(
        subject: subject,
        description: description,
        category: category,
        priority: priority,
      );
    }
    final saved = await SupportApi.instance.open(
      subject: subject,
      description: description,
      category: category,
      priority: priority,
    );
    if (saved == null) {
      return create(
        subject: subject,
        description: description,
        category: category,
        priority: priority,
      );
    }
    _tickets.insert(0, saved);
    notifyListeners();
    return saved.id;
  }

  /// Persisting variant of [addReply]. Routes to admin or patient endpoint
  /// based on the signed-in user's role.
  Future<void> addReplyRemote(String ticketId, String body, {bool isStaff = false}) async {
    if (!AppEnv.backendEnabled) {
      addReply(ticketId, body, isStaff: isStaff);
      return;
    }
    final role = AuthState.instance.role;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      // Admin endpoint returns the updated ticket (not just the reply).
      final raw = await AdminApi.instance.replyToTicket(ticketId, body: body);
      if (raw != null) {
        final updated = PatientDomainMapper.supportTicketFromApi(raw);
        final i = _tickets.indexWhere((t) => t.id == ticketId);
        if (i != -1) _tickets[i] = updated;
        notifyListeners();
        return;
      }
      addReply(ticketId, body, isStaff: isStaff);
      return;
    }
    final reply = await SupportApi.instance.reply(ticketId, body);
    if (reply == null) {
      addReply(ticketId, body, isStaff: isStaff);
      return;
    }
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    final t = _tickets[i];
    _tickets[i] = t.copyWith(
      replies: [...t.replies, reply],
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> resolveRemote(String ticketId) async {
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    if (!AppEnv.backendEnabled) {
      _tickets[i] = _tickets[i].copyWith(
        status: TicketStatus.resolved,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }
    final raw = await AdminApi.instance.resolveTicket(ticketId);
    if (raw == null) return;
    _tickets[i] = PatientDomainMapper.supportTicketFromApi(raw);
    notifyListeners();
  }

  /// Persisting variant for closing a ticket. Routes by role.
  Future<void> closeRemote(String ticketId) async {
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    if (!AppEnv.backendEnabled) {
      _tickets[i] = _tickets[i].copyWith(
        status: TicketStatus.closed,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }
    final role = AuthState.instance.role;
    SupportTicket? saved;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      final raw = await AdminApi.instance.closeTicket(ticketId);
      if (raw != null) saved = PatientDomainMapper.supportTicketFromApi(raw);
    } else {
      saved = await SupportApi.instance.close(ticketId);
    }
    if (saved == null) return;
    _tickets[i] = saved;
    notifyListeners();
  }

  Future<void> reopenRemote(String ticketId) async {
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    if (!AppEnv.backendEnabled) {
      _tickets[i] = _tickets[i].copyWith(
        status: TicketStatus.open,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }
    final saved = await AdminApi.instance.reopenTicket(ticketId);
    if (saved == null) return;
    _tickets[i] = PatientDomainMapper.supportTicketFromApi(saved);
    notifyListeners();
  }

  Future<void> assignRemote(String ticketId, {String? assigneeId}) async {
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i == -1) return;
    if (!AppEnv.backendEnabled) {
      _tickets[i] = _tickets[i].copyWith(
        assignedTo: assigneeId,
        assignedToName: assigneeId == null ? null : 'Staff member',
        updatedAt: DateTime.now(),
        status: assigneeId != null && _tickets[i].status == TicketStatus.open
            ? TicketStatus.inProgress
            : _tickets[i].status,
      );
      notifyListeners();
      return;
    }
    final raw = await AdminApi.instance.assignTicket(
      ticketId,
      assigneeId: assigneeId,
    );
    if (raw == null) return;
    _tickets[i] = PatientDomainMapper.supportTicketFromApi(raw);
    notifyListeners();
  }
}
