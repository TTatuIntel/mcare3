import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared layout blocks for patient module pages (Vitals, Profile, SOS, etc.).
class PatientDateHeader extends StatelessWidget {
  const PatientDateHeader({super.key, this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEEE, MMM d').format(date ?? DateTime.now());
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppPalette.textMuted(context),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class PatientHeroStat extends StatelessWidget {
  const PatientHeroStat({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.onTap,
    this.horizontal = false,
  });

  final String label;
  final String value;
  final Color? accent;
  final VoidCallback? onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: horizontal
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: accent ?? AppPalette.ink(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: accent ?? AppPalette.ink(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
    );

    if (onTap == null) return Expanded(child: child);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: child,
        ),
      ),
    );
  }
}

class PatientHeroStatDivider extends StatelessWidget {
  const PatientHeroStatDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class PatientQuickAction extends StatelessWidget {
  const PatientQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.badgeColor,
    this.selected = false,
    this.iconColor,
    this.horizontal = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;
  final bool selected;
  final Color? iconColor;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = iconColor ?? theme.colorScheme.primary;
    final ink = AppPalette.ink(context);
    final radius = BorderRadius.circular(AppSpacing.radiusSm);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.11)
                : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.34)
                  : Colors.transparent,
            ),
          ),
          child: Semantics(
            button: true,
            selected: selected,
            label: '$label patient section',
            child: Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: horizontal ? 23 : 20, color: accent),
                    if (badge != null)
                      Positioned(
                        right: -9,
                        top: -7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor ?? accent,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusPill,
                            ),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  width: horizontal ? AppSpacing.sm : 0,
                  height: horizontal ? 0 : 3,
                ),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? accent : ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      fontSize: horizontal ? 12 : 10.5,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PatientQuickActionsBar extends StatelessWidget {
  const PatientQuickActionsBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Few actions: equal-width row. Many actions: scroll so mobile labels stay
    // readable instead of crushing into ~9px columns.
    //
    // Five is the limit, not six. On a 360dp phone six equal columns leave
    // about 58dp each, which ellipsises any label longer than one short word —
    // and a row of actions nobody can read is worse than a row they scroll.
    if (children.length <= 5) {
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: 28,
                width: 1,
                color: AppPalette.border(context),
              ),
            Expanded(child: children[i]),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: 28,
                width: 1,
                color: AppPalette.border(context),
              ),
            SizedBox(width: 72, child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Compact label/value row used inside frosted list cards.
class PatientCompactInfoRow extends StatelessWidget {
  const PatientCompactInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PatientCompactToggleRow extends StatelessWidget {
  const PatientCompactToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

String patientRelativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Scrolls a keyed section into view (settings, SOS history, etc.).
void patientScrollToKey(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return;
  Scrollable.ensureVisible(
    ctx,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
    alignment: 0.08,
  );
}
