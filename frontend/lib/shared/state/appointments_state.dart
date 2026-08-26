import 'package:flutter/foundation.dart';

import '../../core/api/appointments_api.dart';
import '../../core/env/app_env.dart';
import '../models/appointment.dart';

class AppointmentsState extends ChangeNotifier {
  AppointmentsState._();
  static final AppointmentsState instance = AppointmentsState._();

  final List<Appointment> _items = [];

  List<Appointment> get all => List.unmodifiable(_items);

  List<Appointment> get upcoming =>
      _items.where((a) => a.isUpcoming).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<Appointment> get past =>
      _items
          .where(
            (a) =>
                !a.isUpcoming &&
                (a.status == AppointmentStatus.completed ||
                    a.scheduledAt.isBefore(DateTime.now())),
          )
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  List<Appointment> get cancelled =>
      _items.where((a) => a.status == AppointmentStatus.cancelled).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  void seed(List<Appointment> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  void add(Appointment a) {
    _items.add(a);
    notifyListeners();
  }

  void cancel(String id, {String? reason}) {
    final i = _items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _items[i] = _items[i].copyWith(
      status: AppointmentStatus.cancelled,
      cancellationReason: reason,
    );
    notifyListeners();
  }

  void confirm(String id) {
    final i = _items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _items[i] = _items[i].copyWith(status: AppointmentStatus.confirmed);
    notifyListeners();
  }

  void reschedule(String id, DateTime newTime) {
    final i = _items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _items[i] = _items[i].copyWith(
      scheduledAt: newTime,
      status: AppointmentStatus.scheduled,
    );
    notifyListeners();
  }

  Appointment? byId(String id) {
    for (final a in _items) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Persisting variant of [add]. POSTs to the API, then inserts the
  /// server-canonical row.
  Future<Appointment> bookAppointment(Appointment draft) async {
    if (!AppEnv.backendEnabled) {
      add(draft);
      return draft;
    }
    final saved = await AppointmentsApi.instance.create(draft);
    final canonical = saved ?? draft;
    _items.add(canonical);
    notifyListeners();
    return canonical;
  }

  /// Persisting variant of [cancel]. PATCHes the appointment with cancelled
  /// status, then updates local state.
  Future<void> cancelAppointment(String id, {String? reason}) async {
    final i = _items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    final original = _items[i];
    _items[i] = original.copyWith(
      status: AppointmentStatus.cancelled,
      cancellationReason: reason,
    );
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      final saved = await AppointmentsApi.instance.update(
        id,
        status: AppointmentStatus.cancelled,
        cancellationReason: reason,
      );
      if (saved != null) {
        final j = _items.indexWhere((a) => a.id == id);
        if (j >= 0) _items[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _items[i] = original;
      notifyListeners();
      rethrow;
    }
  }

  /// Persisting variant of [reschedule].
  Future<void> rescheduleAppointment(String id, DateTime newTime) async {
    final i = _items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    final original = _items[i];
    _items[i] = original.copyWith(
      scheduledAt: newTime,
      status: AppointmentStatus.scheduled,
    );
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      final saved = await AppointmentsApi.instance.update(
        id,
        scheduledAt: newTime,
        status: AppointmentStatus.scheduled,
      );
      if (saved != null) {
        final j = _items.indexWhere((a) => a.id == id);
        if (j >= 0) _items[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _items[i] = original;
      notifyListeners();
      rethrow;
    }
  }
}
