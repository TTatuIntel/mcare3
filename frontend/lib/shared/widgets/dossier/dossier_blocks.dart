import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_dossier.dart';
import '../../models/user_role.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_icons.dart';
import '../glass_card.dart';

/// Presentation primitives shared by every full-profile surface.
///
/// These exist so a patient, a doctor, an assistant, and an admin all read the
/// same way: same hero, same stat strip, same field rows, same timeline. The
/// only thing that changes between roles is which blocks get filled in.

// ---------------------------------------------------------------------------
// Tone
// ---------------------------------------------------------------------------

/// Maps the backend's `good` / `warn` / `bad` / `neutral` classification onto
/// the palette, so tone decisions live server-side and colour lives here.
Color dossierToneColor(BuildContext context, String tone) => switch (tone) {
  'good' => AppColors.success,
  'warn' => AppColors.warning,
  'bad' => AppColors.critical,
  _ => AppColors.info,
};

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// Identity banner: who this is, what they are, and the two dates staff reach
/// for first — when the account opened and when it was last used.
class DossierHero extends StatelessWidget {
  const DossierHero({super.key, required this.dossier});

  final UserDossier dossier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = dossier.account;
    final accent = account.role.accent;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(
                initials: account.initials,
                avatarUrl: account.avatarUrl,
                accent: accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        account.role.label,
                        if (account.uniqueId != null) account.uniqueId,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        DossierPill(
                          label: _statusLabel(account.status),
                          color: _statusColor(account.status),
                        ),
                        if (account.emailVerified)
                          const DossierPill(
                            label: 'Verified',
                            color: AppColors.success,
                            icon: AppIcons.checkMark,
                          )
                        else
                          const DossierPill(
                            label: 'Email unverified',
                            color: AppColors.warning,
                            icon: AppIcons.alert,
                          ),
                        if (dossier.security.isLocked)
                          const DossierPill(
                            label: 'Locked',
                            color: AppColors.critical,
                            icon: AppIcons.lock,
                          ),
                        if (dossier.security.mustChangePassword)
                          const DossierPill(
                            label: 'Temp password',
                            color: AppColors.warning,
                            icon: AppIcons.lock,
                          ),
                        if (!account.profileComplete)
                          const DossierPill(
                            label: 'Profile incomplete',
                            color: AppColors.info,
                            icon: AppIcons.info,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: accent.withValues(alpha: 0.2)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _HeroFact(
                  icon: AppIcons.calendar,
                  label: account.role == UserRole.patient
                      ? 'Account opened'
                      : 'Applied',
                  value: dossierDate(account.createdAt) ?? 'Unknown',
                  hint: account.accountAgeDays == null
                      ? null
                      : '${account.accountAgeDays} days ago',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: accent.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _HeroFact(
                  icon: AppIcons.time,
                  label: 'Last sign-in',
                  value: dossierDate(dossier.security.lastLoginAt) ?? 'Never',
                  hint: dossier.security.loginCount > 0
                      ? '${dossier.security.loginCount} total'
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'active' => 'Active',
    'suspended' => 'Suspended',
    'rejected' => 'Rejected',
    'pendingApproval' || 'pending_approval' || 'pending' => 'Pending approval',
    _ => status,
  };

  static Color _statusColor(String status) => switch (status) {
    'active' => AppColors.success,
    'suspended' || 'rejected' => AppColors.critical,
    _ => AppColors.warning,
  };
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.avatarUrl,
    required this.accent,
  });

  final String initials;
  final String? avatarUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.32)!],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        image: avatarUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(avatarUrl!),
                fit: BoxFit.cover,
              ),
      ),
      alignment: Alignment.center,
      child: avatarUrl != null
          ? null
          : Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppPalette.textMuted(context)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stat strip
// ---------------------------------------------------------------------------

/// Responsive headline numbers. Every metric remains visible without a hidden
/// horizontal strip, matching the clear clinical summary used by doctors.
class DossierStatStrip extends StatelessWidget {
  const DossierStatStrip({super.key, required this.stats});

  final List<DossierStat> stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 3 : 2;
        const gap = AppSpacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: _StatTile(stat: stat),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final DossierStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dossierToneColor(context, stat.tone);

    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section switcher
// ---------------------------------------------------------------------------

/// Segmented control used instead of tabs — the dossier lives inside a
/// scrolling sheet, where a TabBarView would need a fixed height.
class DossierSegments extends StatelessWidget {
  const DossierSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelect,
  });

  final List<String> segments;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? segments.length : 2;
        const gap = AppSpacing.xs;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppPalette.surfaceMuted(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < segments.length; i++)
                SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    label: '${segments[i]} profile section',
                    child: InkWell(
                      onTap: () => onSelect(i),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: i == selected
                              ? accent.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          border: Border.all(
                            color: i == selected
                                ? accent.withValues(alpha: 0.32)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _segmentIcon(segments[i]),
                              size: 16,
                              color: i == selected
                                  ? accent
                                  : AppPalette.textMuted(context),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                segments[i],
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: i == selected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: i == selected
                                      ? accent
                                      : AppPalette.textMuted(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _segmentIcon(String segment) => switch (segment) {
    'Clinical' => AppIcons.vitals,
    'Work' => AppIcons.assignments,
    'Account' => AppIcons.profile,
    'Activity' => AppIcons.audit,
    _ => AppIcons.chart,
  };
}

// ---------------------------------------------------------------------------
// Cards, rows, pills
// ---------------------------------------------------------------------------

/// Titled card wrapping a group of related facts or records.
class DossierCard extends StatelessWidget {
  const DossierCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.emptyMessage,
  });

  final String title;
  final IconData? icon;
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? emptyMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              right: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      actionLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: children.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      emptyMessage ?? 'Nothing recorded.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Label / value pair. Falls back to a muted "Not recorded" so a blank field
/// is never mistaken for a missing section.
class DossierRow extends StatelessWidget {
  const DossierRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasise = false,
  });

  final String label;
  final String? value;
  final Color? valueColor;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = value == null || value!.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              missing ? 'Not recorded' : value!,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: missing
                    ? AppPalette.textFaint(context)
                    : (valueColor ?? AppPalette.ink(context)),
                fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
                fontStyle: missing ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A record line: title, supporting detail, and an optional status chip.
class DossierRecordRow extends StatelessWidget {
  const DossierRecordRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.badge,
    this.badgeColor,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final String? badge;
  final Color? badgeColor;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = iconColor ?? theme.colorScheme.primary;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (badge != null)
                DossierPill(label: badge!, color: badgeColor ?? AppColors.info),
              if (meta != null)
                Padding(
                  padding: EdgeInsets.only(top: badge != null ? 3 : 0),
                  child: Text(
                    meta!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: content,
    );
  }
}

class DossierPill extends StatelessWidget {
  const DossierPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical event stream with a connecting rail — the account's history read
/// top to bottom.
class DossierTimeline extends StatelessWidget {
  const DossierTimeline({super.key, required this.events, this.limit = 12});

  final List<DossierEvent> events;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'No recorded history.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      );
    }

    final shown = events.take(limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 11),
                      height: 9,
                      width: 9,
                      decoration: BoxDecoration(
                        color: _kindColor(shown[i].kind),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (i != shown.length - 1)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: AppPalette.border(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shown[i].title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            dossierDateTime(shown[i].at),
                            if (shown[i].detail != null) shown[i].detail,
                          ].whereType<String>().join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                            fontSize: 10,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color _kindColor(String kind) => switch (kind) {
    'created' => AppColors.info,
    'verified' || 'approved' => AppColors.success,
    'rejected' || 'locked' => AppColors.critical,
    'login' => AppColors.brandIndigo,
    _ => AppColors.textMutedAA,
  };
}

/// Wrapping chip list — assigned vitals, permissions, languages.
class DossierChips extends StatelessWidget {
  const DossierChips({
    super.key,
    required this.labels,
    this.color,
    this.emptyMessage = 'None',
  });

  final List<String> labels;
  final Color? color;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          emptyMessage,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.textMuted(context)),
        ),
      );
    }
    final tint = color ?? AppColors.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final label in labels) DossierPill(label: label, color: tint),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

String? dossierDate(DateTime? d) =>
    d == null ? null : DateFormat('d MMM yyyy').format(d);

String? dossierDateTime(DateTime? d) =>
    d == null ? null : DateFormat('d MMM yyyy, HH:mm').format(d);

/// "3 days ago" / "in 2 hours" — relative phrasing for recency-sensitive rows.
String dossierRelative(DateTime d) {
  final diff = DateTime.now().difference(d);
  final future = diff.isNegative;
  final abs = diff.abs();

  String unit;
  if (abs.inMinutes < 1) {
    return 'just now';
  } else if (abs.inMinutes < 60) {
    unit = '${abs.inMinutes} min';
  } else if (abs.inHours < 24) {
    unit = '${abs.inHours} hr';
  } else if (abs.inDays < 30) {
    unit = '${abs.inDays} day${abs.inDays == 1 ? '' : 's'}';
  } else if (abs.inDays < 365) {
    final m = (abs.inDays / 30).floor();
    unit = '$m month${m == 1 ? '' : 's'}';
  } else {
    final y = (abs.inDays / 365).floor();
    unit = '$y year${y == 1 ? '' : 's'}';
  }

  return future ? 'in $unit' : '$unit ago';
}

/// Turns a snake_case backend enum into human text.
String dossierHumanize(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final spaced = raw.replaceAll('_', ' ').trim();
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Risk band colouring shared by vitals and alert rows.
Color dossierRiskColor(String? risk) => switch (risk) {
  'critical' => AppColors.critical,
  'warning' => AppColors.warning,
  'normal' => AppColors.success,
  _ => AppColors.textMutedAA,
};
