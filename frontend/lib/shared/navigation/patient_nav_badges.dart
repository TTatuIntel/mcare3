import 'package:flutter/foundation.dart';

import '../constants/route_names.dart';
import '../models/medication.dart';
import '../state/medications_state.dart';
import '../state/messages_state.dart';
import '../state/notification_state.dart';
import '../state/report_consents_state.dart';

/// Live counts behind the patient's four tabs.
///
/// The tabs are the patient's map of the app, so they have to say what is
/// waiting behind them the moment it lands — the session poller and the
/// realtime channel already push into these stores, and [listenable] is what
/// carries that through to the nav, the desktop rail and the hub tiles so all
/// three agree on one number.
abstract final class PatientNavBadges {
  /// Every store a tab badge reads. Built once: an [AnimatedBuilder] rebuilt
  /// against a fresh merge on each frame would resubscribe on every build.
  static final Listenable listenable = Listenable.merge([
    MedicationsState.instance,
    MessagesState.instance,
    NotificationState.instance,
    ReportConsentsState.instance,
  ]);

  /// Doses the patient still owes today — scheduled for now or earlier and
  /// neither taken nor skipped. A dose due tonight is not yet a nag, so it is
  /// deliberately left out until its time comes.
  static int get health {
    final now = DateTime.now();
    return MedicationsState.instance
        .dosesForToday()
        .where(
          (d) =>
              (d.status == DoseStatus.pending &&
                  !d.scheduledAt.isAfter(now)) ||
              d.status == DoseStatus.missed,
        )
        .length;
  }

  /// Unread messages from the care team.
  static int get care => MessagesState.instance.totalUnread;

  /// Unread notifications. This is the count for the Notifications tile
  /// itself, which holds nothing but the inbox.
  static int get inbox => NotificationState.instance.unreadCount;

  /// Sharing requests the patient has neither approved nor declined. These
  /// block staff work and expire on a timer, so they are counted separately
  /// from the inbox and never fall off it once the notification is read.
  static int get sharingRequests => ReportConsentsState.instance.awaitingCount;

  /// The More tab covers both surfaces behind it, so its badge is the sum.
  static int get more => inbox + sharingRequests;

  /// Count for [route], or 0 when that tab has nothing outstanding. Home is
  /// deliberately never badged: it is where everything is already summarised.
  static int forRoute(String route) => switch (route) {
    RouteNames.patientHealth => health,
    RouteNames.patientCare => care,
    RouteNames.patientMore => more,
    _ => 0,
  };
}
