import '../state/settings_state.dart';

enum SettingsNotificationRole { patient, doctor, admin, assistant }

/// One notification toggle bound to [SettingsState.toggleNotification].
class NotificationToggleDef {
  const NotificationToggleDef({
    required this.key,
    required this.label,
    this.subtitle,
  });

  final String key;
  final String label;
  final String? subtitle;

  bool value(SettingsState s) {
    final n = s.notifications;
    return switch (key) {
      'vitalAlerts' => n.vitalAlerts,
      'appointmentReminders' => n.appointmentReminders,
      'medicationReminders' => n.medicationReminders,
      'messages' => n.messages,
      'reports' => n.reports,
      'pushEnabled' => n.pushEnabled,
      'smsEnabled' => n.smsEnabled,
      'emailEnabled' => n.emailEnabled,
      _ => false,
    };
  }

  void apply(SettingsState s, bool v) => s.toggleNotification(key, v);
}

/// Preset notification toggle sets per role.
class SettingsNotificationPresets {
  SettingsNotificationPresets._();

  static const patientMaster = NotificationToggleDef(
    key: '_master_patient',
    label: 'All notifications',
    subtitle: 'Turn every alert channel on or off',
  );

  static const doctorMaster = NotificationToggleDef(
    key: '_master_doctor',
    label: 'All notifications',
    subtitle: 'Turn every alert channel on or off',
  );

  static const adminMaster = NotificationToggleDef(
    key: '_master_admin',
    label: 'All admin alerts',
    subtitle: 'Master switch for operational notifications',
  );

  static const patient = [
    NotificationToggleDef(
      key: 'vitalAlerts',
      label: 'Vital alerts',
      subtitle: 'When readings need attention',
    ),
    NotificationToggleDef(
      key: 'appointmentReminders',
      label: 'Appointment reminders',
    ),
    NotificationToggleDef(
      key: 'medicationReminders',
      label: 'Medication reminders',
    ),
    NotificationToggleDef(key: 'messages', label: 'New messages'),
    NotificationToggleDef(key: 'pushEnabled', label: 'Push notifications'),
    NotificationToggleDef(key: 'smsEnabled', label: 'SMS alerts'),
    NotificationToggleDef(key: 'emailEnabled', label: 'Email digests'),
  ];

  static const doctor = [
    NotificationToggleDef(
      key: 'vitalAlerts',
      label: 'Critical vital alerts',
      subtitle: 'Cannot be silenced on safety grounds',
    ),
    NotificationToggleDef(
      key: 'appointmentReminders',
      label: 'Appointment reminders',
    ),
    NotificationToggleDef(key: 'messages', label: 'New messages'),
    NotificationToggleDef(key: 'reports', label: 'Report updates'),
    NotificationToggleDef(key: 'pushEnabled', label: 'Push notifications'),
    NotificationToggleDef(key: 'emailEnabled', label: 'Email digests'),
  ];

  static const admin = [
    NotificationToggleDef(
      key: 'vitalAlerts',
      label: 'Critical vital alerts',
      subtitle: 'System-wide patient vital warnings',
    ),
    NotificationToggleDef(
      key: 'medicationReminders',
      label: 'SOS & emergencies',
      subtitle: 'Active SOS events across the platform',
    ),
    NotificationToggleDef(
      key: 'appointmentReminders',
      label: 'Approval queue',
      subtitle: 'Healthworker registration requests',
    ),
    NotificationToggleDef(
      key: 'reports',
      label: 'Security & audit',
      subtitle: 'Incidents and sensitive activity',
    ),
    NotificationToggleDef(
      key: 'messages',
      label: 'Messages & support',
      subtitle: 'Staff threads and support tickets',
    ),
    NotificationToggleDef(key: 'pushEnabled', label: 'Push notifications'),
    NotificationToggleDef(key: 'emailEnabled', label: 'Email digests'),
  ];
}
