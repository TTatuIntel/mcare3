/// Optional route arguments for [NotificationsView].
class NotificationsFilter {
  const NotificationsFilter({this.showResolved = false});

  final bool showResolved;

  static NotificationsFilter? tryParse(Object? args) {
    if (args is NotificationsFilter) return args;
    if (args is bool) return NotificationsFilter(showResolved: args);
    return null;
  }
}
