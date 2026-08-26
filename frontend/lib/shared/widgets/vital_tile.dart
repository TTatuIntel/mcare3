import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_item.dart';
import '../models/vital.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';
import 'risk_badge.dart';

enum VitalTileVariant { card, compact }

/// Compact tile showing latest reading for one vital.
class VitalTile extends StatelessWidget {
  const VitalTile({
    super.key,
    required this.vital,
    required this.reading,
    this.onTap,
    this.alert,
    this.resolvedAlert,
    this.frosted = true,
    this.assigned = false,
    this.variant = VitalTileVariant.card,
  });

  final VitalKey vital;
  final VitalReading? reading;
  final VoidCallback? onTap;
  final AppNotification? alert;
  final AppNotification? resolvedAlert;
  final bool frosted;
  final bool assigned;
  final VitalTileVariant variant;

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(t);
  }

  bool get _isResolved =>
      alert == null &&
      resolvedAlert != null &&
      (reading?.risk == RiskLevel.normal);

  String? _footerDetail(RiskLevel risk) {
    if (alert != null) return alert!.title;
    return null;
  }

  Color _footerColor(BuildContext context, RiskLevel risk) {
    if (alert != null) return alert!.kind.tint;
    if (_isResolved) return AppColors.success;
    return AppPalette.textMuted(context);
  }

  Widget _statusBadge(BuildContext context, RiskLevel risk, ThemeData theme) {
    if (_isResolved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppPalette.successSoft(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: Text(
          'Resolved',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      );
    }
    return RiskBadge(risk: risk, dense: true);
  }

  Widget _tileBody(BuildContext context) {
    final theme = Theme.of(context);
    final risk = reading?.risk ?? RiskLevel.unknown;
    final accent = vital.accent;
    final value = reading?.formatValue() ?? '—';
    final when = reading == null
        ? 'Not logged'
        : _relative(reading!.recordedAt);
    final compact = variant == VitalTileVariant.compact;

    final iconBox = Container(
      height: compact ? 34 : 42,
      width: compact ? 34 : 42,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(
          compact ? AppSpacing.radiusSm : AppSpacing.radiusMd,
        ),
        border: compact ? null : Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Icon(vital.icon, color: accent, size: compact ? 17 : 21),
    );

    return Row(
      children: [
        iconBox,
        SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vital.label,
                      style:
                          (compact
                                  ? theme.textTheme.labelMedium
                                  : theme.textTheme.labelLarge)
                              ?.copyWith(
                                fontWeight: compact
                                    ? FontWeight.w700
                                    : FontWeight.w800,
                                height: 1.1,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (assigned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppColors.brandIndigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                        border: Border.all(
                          color: AppColors.brandIndigo.withOpacity(0.22),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            AppIcons.lock,
                            size: 10,
                            color: AppColors.brandIndigo,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Assigned',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.brandIndigo,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _statusBadge(context, risk, theme),
                ],
              ),
              SizedBox(height: compact ? 2 : 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style:
                          (compact
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                    ),
                    TextSpan(
                      text: reading == null ? '' : ' ${vital.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: compact ? 1 : 2),
              Text(
                () {
                  final detail = _footerDetail(risk);
                  if (reading == null) return 'Not logged yet';
                  if (detail != null) return '$when · $detail';
                  return when;
                }(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _footerColor(context, risk),
                  fontSize: 10,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (alert != null) ...[
          const SizedBox(width: 4),
          Icon(
            AppIcons.alert,
            size: compact ? 14 : 16,
            color: alert!.kind.tint,
          ),
        ] else if (_isResolved) ...[
          const SizedBox(width: 4),
          Icon(
            AppIcons.check,
            size: compact ? 14 : 16,
            color: AppColors.success,
          ),
        ],
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(
            AppIcons.chevronRight,
            size: compact ? 16 : 18,
            color: accent.withOpacity(0.65),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final risk = reading?.risk ?? RiskLevel.unknown;
    final alertTint = alert?.kind.tint;

    if (variant == VitalTileVariant.compact) {
      return Semantics(
        label: '${vital.label} ${reading?.formatValue() ?? 'no reading'}',
        button: onTap != null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: _isResolved
                    ? AppPalette.successSoft(context).withOpacity(0.45)
                    : risk == RiskLevel.normal
                    ? (AppPalette.isDark(context)
                          ? AppColors.darkSurfaceAlt.withOpacity(0.65)
                          : Colors.white.withOpacity(0.28))
                    : risk.softBg(context).withOpacity(0.55),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: _isResolved
                      ? AppColors.success.withOpacity(0.35)
                      : alertTint != null
                      ? alertTint.withOpacity(0.4)
                      : risk.color.withOpacity(
                          risk == RiskLevel.normal ? 0.14 : 0.24,
                        ),
                ),
              ),
              child: _tileBody(context),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      frosted: frosted,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: _tileBody(context),
    );
  }
}
