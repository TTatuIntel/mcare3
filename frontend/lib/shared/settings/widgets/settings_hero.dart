import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/patient_page_blocks.dart';

/// Hero summary card at the top of settings screens (all roles).
class SettingsHero extends StatelessWidget {
  const SettingsHero({
    super.key,
    required this.title,
    required this.accent,
    required this.themeLabel,
    required this.language,
    required this.notificationsOn,
    this.onThemeTap,
    this.onLanguageTap,
    this.onAlertsTap,
  });

  final String title;
  final Color accent;
  final String themeLabel;
  final String language;
  final int notificationsOn;
  final VoidCallback? onThemeTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onAlertsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(AppIcons.settings, color: accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              '$themeLabel · $language',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              PatientHeroStat(
                label: 'Theme',
                value: themeLabel,
                onTap: onThemeTap,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Language',
                value: language,
                onTap: onLanguageTap,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Alerts on',
                value: '$notificationsOn',
                onTap: onAlertsTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
