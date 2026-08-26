import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/notification_components.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';

/// Patient notifications — same shared panel as doctor/admin/assistant.
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key, this.initialShowResolved = false});

  final bool initialShowResolved;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final todayStr = DateFormat('EEEE, MMM d').format(DateTime.now());

    return PatientScaffold(
      currentRoute: RouteNames.patientNotifications,
      detachedNav: true,
      title: 'Notifications',
      subtitle: 'Alerts, reminders and care updates',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            todayStr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          NotificationsPanel(
            initialShowResolved: initialShowResolved,
            showVitalResolvedCount: true,
          ),
          SizedBox(height: tier.isHandheld ? 24 : AppSpacing.huge),
        ],
      ),
    );
  }
}
