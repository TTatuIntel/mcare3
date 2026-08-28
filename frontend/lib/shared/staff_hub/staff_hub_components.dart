import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import 'staff_hub_models.dart';

class StaffHubSurface extends StatelessWidget {
  const StaffHubSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: borderColor ?? AppPalette.border(context)),
      boxShadow: AppShadows.card(context),
    );
    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

/// Section heading with an optional description behind an info button.
///
/// The description used to fade in on mount and collapse itself after four
/// seconds. Every heading on a page did that independently, so the layout
/// shrank under the operator's fingers seconds after arriving — cards slid
/// upward while they were reaching for one, which reads as the app moving on
/// its own. Nothing here changes size unless the operator asks it to.
class StaffHubSectionHeading extends StatefulWidget {
  const StaffHubSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<StaffHubSectionHeading> createState() => _StaffHubSectionHeadingState();
}

class _StaffHubSectionHeadingState extends State<StaffHubSectionHeading> {
  static const Duration _animate = Duration(milliseconds: 260);

  /// Collapsed by default and toggled only by the info button, so the page
  /// settles once and stays put. No timer: layout must never move on a clock.
  bool _showSubtitle = false;

  void _toggle() => setState(() => _showSubtitle = !_showSubtitle);

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    final hasSubtitle = subtitle != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: AppPalette.ink(context)),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _SectionInfoButton(
                      tooltip: _showSubtitle
                          ? 'Hide description'
                          : 'Show description',
                      enabled: hasSubtitle,
                      onTap: hasSubtitle ? _toggle : null,
                    ),
                  ],
                ],
              ),
              if (subtitle != null)
                AnimatedSize(
                  duration: _animate,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: AnimatedOpacity(
                    duration: _animate,
                    curve: Curves.easeOut,
                    opacity: _showSubtitle ? 1 : 0,
                    child: _showSubtitle
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppPalette.textMuted(context),
                                  ),
                            ),
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ),
            ],
          ),
        ),
        ?widget.trailing,
      ],
    );
  }
}

class _SectionInfoButton extends StatelessWidget {
  const _SectionInfoButton({
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppPalette.textMuted(context)
        : AppPalette.textMuted(context).withValues(alpha: 0.45);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(AppIcons.info, size: 16, color: color),
        ),
      ),
    );
  }
}

class StaffHubTaskCard extends StatelessWidget {
  const StaffHubTaskCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    this.count = 0,
    this.horizontal = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return StaffHubSurface(
        onTap: onTap,
        borderColor: color.withValues(alpha: 0.22),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _TintedIcon(icon: icon, color: color, size: 38),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.ink(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (count > 0) ...[
              StaffHubCountBadge(count: count, color: color),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(
              AppIcons.chevronRight,
              size: 20,
              color: AppPalette.textMuted(context),
            ),
          ],
        ),
      );
    }
    return StaffHubSurface(
      onTap: onTap,
      borderColor: color.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TintedIcon(icon: icon, color: color, size: 44),
              const Spacer(),
              if (count > 0) StaffHubCountBadge(count: count, color: color),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(AppIcons.chevronRight, color: AppPalette.textMuted(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}

class StaffHubCountBadge extends StatelessWidget {
  const StaffHubCountBadge({
    super.key,
    required this.count,
    required this.color,
  });

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class StaffHubWorkRow extends StatelessWidget {
  const StaffHubWorkRow({
    super.key,
    required this.item,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final StaffWorkItem item;
  final Color accent;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${item.title}, ${item.count} items, ${item.actionLabel}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _TintedIcon(icon: item.icon, color: item.color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${item.count} ${item.count == 1 ? 'item' : 'items'} · ${item.description}',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (!compact)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: onTap,
                  child: Text(item.actionLabel),
                )
              else
                Icon(
                  AppIcons.chevronRight,
                  color: AppPalette.textMuted(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StaffHubLinkTile extends StatelessWidget {
  const StaffHubLinkTile({super.key, required this.link, required this.onTap});

  final StaffHubLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StaffHubSurface(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            _TintedIcon(icon: link.icon, color: link.color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.ink(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    link.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            if (link.count case final count?) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: link.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            Icon(AppIcons.chevronRight, color: AppPalette.textMuted(context)),
          ],
        ),
      ),
    );
  }
}

class StaffHubMetric extends StatelessWidget {
  const StaffHubMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
    this.sublabel,
    this.badgeCount,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  /// Optional secondary line — used for the analytics breakdown
  /// (e.g. "Doctors 3 · Admins 1 · Assistants 1").
  final String? sublabel;

  /// Optional attention badge. When > 0 a pill is rendered near the icon and,
  /// on non-compact layouts, the surface border tints with [color].
  final int? badgeCount;

  /// When provided, the tile becomes tappable via [StaffHubSurface].
  final VoidCallback? onTap;

  bool get _hasBadge => (badgeCount ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return StaffHubSurface(
        onTap: onTap,
        borderColor: _hasBadge ? color.withValues(alpha: 0.35) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
                if (_hasBadge)
                  StaffHubCountBadge(count: badgeCount!, color: color),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppPalette.ink(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
                height: 1.15,
              ),
            ),
            if (sublabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                sublabel!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return StaffHubSurface(
      onTap: onTap,
      borderColor: _hasBadge ? color.withValues(alpha: 0.35) : null,
      child: Row(
        children: [
          _TintedIcon(icon: icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: AppPalette.ink(context)),
                      ),
                    ),
                    if (_hasBadge)
                      StaffHubCountBadge(count: badgeCount!, color: color),
                  ],
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
                if (sublabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    sublabel!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            Icon(AppIcons.chevronRight, color: AppPalette.textMuted(context)),
        ],
      ),
    );
  }
}

class StaffHubEmptyState extends StatelessWidget {
  const StaffHubEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = AppIcons.check,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return StaffHubSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            _TintedIcon(icon: icon, color: AppColors.success, size: 58),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StaffHubPermissionNotice extends StatelessWidget {
  const StaffHubPermissionNotice({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    if (role != UserRole.mcareAssistant) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.mcareAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.mcareAmber.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.permissions, color: AppColors.mcareAmber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Only workspaces allowed by your current delegated permissions are shown.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppPalette.ink(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TintedIcon extends StatelessWidget {
  const _TintedIcon({required this.icon, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
