/// A platform announcement authored by an admin and addressed to an audience.
///
/// The backend only ever hands the patient app announcements that are
/// published and inside their display window, so the client treats every
/// item it receives as live.
class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.audience = 'all',
    this.ctaLabel,
    this.ctaUrl,
    this.startsAt,
    this.endsAt,
    this.createdBy,
  });

  final String id;
  final String title;
  final String body;
  final String audience;
  final String? ctaLabel;
  final String? ctaUrl;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? createdBy;
  final DateTime createdAt;

  /// The moment this announcement started mattering — the scheduled start
  /// when there is one, otherwise when it was written.
  DateTime get effectiveAt => startsAt ?? createdAt;

  bool get hasLink => (ctaUrl ?? '').trim().isNotEmpty;

  /// True while the announcement is inside its scheduled window. The server
  /// filters already; this guards the mock layer and any cached payload that
  /// outlived its `ends_at`.
  bool isLiveAt(DateTime now) {
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }
}
