/// Time-of-day greeting shared by staff shells, dashboards, and headers.
String timeGreeting({String? firstName, String? prefix}) {
  final hour = DateTime.now().hour;
  final base = hour < 12
      ? 'Good morning'
      : (hour < 18 ? 'Good afternoon' : 'Good evening');
  if (firstName == null || firstName.trim().isEmpty) return base;
  final name = prefix != null ? '$prefix${firstName.trim()}' : firstName.trim();
  return '$base, $name';
}
