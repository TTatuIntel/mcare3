import 'package:flutter/material.dart';

import '../settings_definitions.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/patient_page_blocks.dart';

/// Notification toggles shared across role settings screens.
class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({
    super.key,
    this.sectionKey,
    required this.role,
    this.toggles,
  });

  final Key? sectionKey;
  final SettingsNotificationRole role;
  final List<NotificationToggleDef>? toggles;

  List<NotificationToggleDef> get _toggles =>
      toggles ??
      switch (role) {
        SettingsNotificationRole.patient => SettingsNotificationPresets.patient,
        SettingsNotificationRole.doctor || SettingsNotificationRole.assistant =>
          SettingsNotificationPresets.doctor,
        SettingsNotificationRole.admin => SettingsNotificationPresets.admin,
      };

  NotificationToggleDef get _master => switch (role) {
    SettingsNotificationRole.patient =>
      SettingsNotificationPresets.patientMaster,
    SettingsNotificationRole.doctor || SettingsNotificationRole.assistant =>
      SettingsNotificationPresets.doctorMaster,
    SettingsNotificationRole.admin => SettingsNotificationPresets.adminMaster,
  };

  bool _masterValue(SettingsState s) => switch (role) {
    SettingsNotificationRole.patient => s.allPatientNotificationsOn,
    SettingsNotificationRole.doctor ||
    SettingsNotificationRole.assistant => s.allDoctorNotificationsOn,
    SettingsNotificationRole.admin => s.allAdminNotificationsOn,
  };

  void _setMaster(SettingsState s, bool v) {
    switch (role) {
      case SettingsNotificationRole.patient:
        s.setAllPatientNotifications(v);
      case SettingsNotificationRole.doctor:
      case SettingsNotificationRole.assistant:
        s.setAllDoctorNotifications(v);
      case SettingsNotificationRole.admin:
        s.setAllAdminNotifications(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsState.instance;

    return KeyedSubtree(
      key: sectionKey,
      child: GlassCard(
        frosted: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          children: [
            PatientCompactToggleRow(
              label: _master.label,
              subtitle: _master.subtitle,
              value: _masterValue(s),
              onChanged: (v) {
                _setMaster(s, v);
                AppToast.success(
                  context,
                  v ? 'All alerts enabled' : 'All alerts paused',
                );
              },
            ),
            Divider(height: 1, color: AppPalette.border(context)),
            for (final t in _toggles)
              PatientCompactToggleRow(
                label: t.label,
                subtitle: t.subtitle,
                value: t.value(s),
                onChanged: (v) => t.apply(s, v),
              ),
          ],
        ),
      ),
    );
  }
}
