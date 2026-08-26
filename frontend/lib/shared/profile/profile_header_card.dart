import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/patient_page_blocks.dart';
import '../widgets/profile_completion_heart.dart';

/// A single at-a-glance stat rendered in the header footer (e.g. BMI, Contacts).
class ProfileHeaderStat {
  const ProfileHeaderStat({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;
}

/// Unified profile hero used by every role (patient, doctor, admin, assistant).
///
/// Renders the avatar, name, role badge + mCare ID, email/phone, a completion
/// ring and an edit/complete action — so all profile screens open the same way.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.user,
    required this.completionPercent,
    this.onEdit,
    this.editLabel,
    this.stats = const [],
    this.warning,
  });

  final AppUser user;
  final int completionPercent;
  final VoidCallback? onEdit;
  final String? editLabel;
  final List<ProfileHeaderStat> stats;

  /// Optional highlighted banner (e.g. "Complete your profile").
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = user.role.accent;
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: accent.withValues(alpha: 0.15),
                backgroundImage: hasPhoto
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: hasPhoto
                    ? null
                    : Text(
                        user.initials,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(label: user.role.label, color: accent),
                        _Chip(
                          label: 'ID ${user.uniqueId}',
                          color: AppPalette.textMuted(context),
                          subtle: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.phone != null && user.phone!.trim().isNotEmpty)
                      Text(
                        user.phone!.trim(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                children: [
                  ProfileCompletionHeart(
                    percent: completionPercent,
                    size: 44,
                    showLabel: true,
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppButton.icon(
                      icon: AppIcons.edit,
                      semanticLabel: editLabel ?? 'Edit profile',
                      onPressed: onEdit,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.alert, size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      warning!,
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: AppPalette.border(context)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const PatientHeroStatDivider(),
                  PatientHeroStat(
                    label: stats[i].label,
                    value: stats[i].value,
                    accent: stats[i].accent,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.subtle = false});

  final String label;
  final Color color;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: subtle ? 0.1 : 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
        ),
      ),
    );
  }
}
