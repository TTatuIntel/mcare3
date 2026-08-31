import 'package:flutter/foundation.dart';

import '../models/announcement.dart';

/// Platform announcements delivered to the signed-in user.
///
/// Seeded from `GET /patient/session` (`announcements`), which already filters
/// by audience and schedule. Dismissals are session-scoped: they hide an
/// announcement from the home feed without pretending the server was told.
class AnnouncementsState extends ChangeNotifier {
  AnnouncementsState._();
  static final AnnouncementsState instance = AnnouncementsState._();

  final List<AppAnnouncement> _items = [];
  final Set<String> _dismissed = {};

  List<AppAnnouncement> get all => List.unmodifiable(_items);

  /// Announcements inside their display window and not dismissed this session,
  /// newest first.
  List<AppAnnouncement> get live {
    final now = DateTime.now();
    return _items
        .where((a) => !_dismissed.contains(a.id) && a.isLiveAt(now))
        .toList(growable: false);
  }

  bool isDismissed(String id) => _dismissed.contains(id);

  void seed(List<AppAnnouncement> items) {
    _items
      ..clear()
      ..addAll(items)
      ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
    // Drop dismissals for announcements that no longer exist so the set does
    // not grow across re-syncs.
    final ids = _items.map((a) => a.id).toSet();
    _dismissed.removeWhere((id) => !ids.contains(id));
    notifyListeners();
  }

  void dismiss(String id) {
    if (_dismissed.add(id)) notifyListeners();
  }

  void restoreAll() {
    if (_dismissed.isEmpty) return;
    _dismissed.clear();
    notifyListeners();
  }
}
