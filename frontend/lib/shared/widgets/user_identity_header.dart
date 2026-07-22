import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Avatar + name + email + role line — shared by profile sheet and profile page.
class UserIdentityHeader extends StatelessWidget {
  const UserIdentityHeader({
    super.key,
    required this.user,
    this.avatarRadius = 26,
    this.showPhone = true,
    this.trailing,
  });

  final AppUser user;
  final double avatarRadius;
  final bool showPhone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: avatarRadius,
          backgroundColor: user.role.accent.withValues(alpha: 0.15),
          backgroundImage: hasPhoto ? NetworkImage(user.avatarUrl!) : null,
          child: hasPhoto
              ? null
              : Text(
                  user.initials,
                  style: TextStyle(
                    color: user.role.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: avatarRadius > 22 ? null : 12,
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.ink(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                user.email,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
              ),
              Text(
                '${user.role.label} · ${user.uniqueId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
              ),
              if (showPhone &&
                  user.phone != null &&
                  user.phone!.trim().isNotEmpty)
                Text(
                  user.phone!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
