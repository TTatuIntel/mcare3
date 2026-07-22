import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../patients/doctor_patient_section.dart';

/// Primary workspace tabs (always visible) + overflow sheet for the rest.
class DoctorPatientQuickLinks extends StatelessWidget {
  const DoctorPatientQuickLinks({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.badges,
  });

  final DoctorPatientSection selected;
  final ValueChanged<DoctorPatientSection> onSelected;
  final Map<DoctorPatientSection, int> badges;

  static const primary = [
    DoctorPatientSection.overview,
    DoctorPatientSection.vitals,
    DoctorPatientSection.appointments,
    DoctorPatientSection.prescriptions,
  ];

  static const overflow = [
    DoctorPatientSection.trends,
    DoctorPatientSection.alerts,
    DoctorPatientSection.sos,
    DoctorPatientSection.documents,
    DoctorPatientSection.messages,
    DoctorPatientSection.reports,
    DoctorPatientSection.timeline,
    DoctorPatientSection.meals,
  ];

  int get _overflowBadgeTotal {
    var n = 0;
    for (final s in overflow) {
      final b = badges[s];
      if (b != null && b > 0) n += b;
    }
    return n;
  }

  bool get _overflowHasSelection =>
      overflow.contains(selected) && !primary.contains(selected);

  Future<void> _openOverflow(BuildContext context) async {
    final chosen = await GlassSheet.show<DoctorPatientSection>(
      context,
      title: 'More patient tools',
      subtitle: 'Alerts, documents, messages and more',
      maxHeightFactor: 0.55,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final tileWidth =
              (constraints.maxWidth - AppSpacing.sm * 2) / 3;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in overflow)
                SizedBox(
                  width: tileWidth,
                  child: PatientQuickAction(
                    icon: s.icon,
                    label: s.label,
                    selected: selected == s,
                    badge: () {
                      final c = badges[s];
                      return c != null && c > 0 ? '$c' : null;
                    }(),
                    badgeColor: s == DoctorPatientSection.sos
                        ? AppColors.critical
                        : AppColors.brandIndigo,
                    iconColor: s == DoctorPatientSection.sos
                        ? AppColors.critical
                        : null,
                    onTap: () =>
                        Navigator.of(ctx, rootNavigator: true).pop(s),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      child: Row(
        children: [
          for (var i = 0; i < primary.length; i++) ...[
            if (i > 0)
              Container(height: 24, width: 1, color: AppPalette.border(context)),
            Expanded(
              child: _LinkTile(
                section: primary[i],
                selected: selected == primary[i],
                badge: badges[primary[i]],
                onTap: () => onSelected(primary[i]),
              ),
            ),
          ],
          Container(height: 24, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: PatientQuickAction(
              icon: AppIcons.more,
              label: 'More',
              selected: _overflowHasSelection,
              badge: _overflowBadgeTotal > 0 ? '$_overflowBadgeTotal' : null,
              onTap: () {
                if (_overflowHasSelection) {
                  _openOverflow(context);
                } else if (_overflowBadgeTotal > 0) {
                  if ((badges[DoctorPatientSection.alerts] ?? 0) > 0) {
                    onSelected(DoctorPatientSection.alerts);
                  } else if ((badges[DoctorPatientSection.sos] ?? 0) > 0) {
                    onSelected(DoctorPatientSection.sos);
                  } else {
                    _openOverflow(context);
                  }
                } else {
                  _openOverflow(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.section,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final DoctorPatientSection section;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final count = badge;
    return PatientQuickAction(
      icon: section.icon,
      label: section.label,
      selected: selected,
      badge: count != null && count > 0 ? '$count' : null,
      badgeColor: section == DoctorPatientSection.sos
          ? AppColors.critical
          : AppColors.brandIndigo,
      iconColor:
          section == DoctorPatientSection.sos ? AppColors.critical : null,
      onTap: onTap,
    );
  }
}
