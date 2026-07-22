import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/patient_page_blocks.dart';

/// Quick-action chip definitions for settings screens.
class SettingsQuickActionDef {
  const SettingsQuickActionDef({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
}

class SettingsQuickActionsBar extends StatelessWidget {
  const SettingsQuickActionsBar({super.key, required this.actions});

  final List<SettingsQuickActionDef> actions;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: PatientQuickActionsBar(
        children: actions
            .map(
              (a) => PatientQuickAction(
                icon: a.icon,
                label: a.label,
                badge: a.badge,
                onTap: a.onTap,
              ),
            )
            .toList(),
      ),
    );
  }
}
