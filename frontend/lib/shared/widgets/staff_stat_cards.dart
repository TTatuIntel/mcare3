import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'glass_card.dart';

/// Data for one clickable staff stat tile.
class StaffStatCardData {
  const StaffStatCardData({
    required this.value,
    required this.label,
    required this.detail,
    required this.icon,
    required this.accent,
    this.onTap,
    this.pulse = false,
    this.cardKey,
  });

  final String value;
  final String label;
  final String detail;
  final IconData icon;
  final Color accent;

  /// Tap handler. When null the card renders as a static (non-tappable) tile
  /// with no chevron affordance.
  final VoidCallback? onTap;
  final bool pulse;
  final Key? cardKey;
}

/// 2-column grid of tappable stat cards for staff dashboards.
class StaffStatCardsGrid extends StatelessWidget {
  const StaffStatCardsGrid({super.key, required this.cards});

  final List<StaffStatCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.xs;
        final w = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (c) => SizedBox(
                  width: w,
                  child: StaffStatCard(key: c.cardKey, data: c),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class StaffStatCard extends StatefulWidget {
  const StaffStatCard({super.key, required this.data});

  final StaffStatCardData data;

  @override
  State<StaffStatCard> createState() => _StaffStatCardState();
}

class _StaffStatCardState extends State<StaffStatCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant StaffStatCard old) {
    super.didUpdateWidget(old);
    if (widget.data.pulse != old.data.pulse) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.data.pulse) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    final muted = AppPalette.textMuted(context);
    final valueColor =
        data.accent == AppPalette.textMuted(context) || data.accent == muted
        ? null
        : data.accent;

    Widget card = GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 14, color: data.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: muted,
                    fontSize: 11,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                data.value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  height: 1,
                ),
              ),
              if (data.onTap != null) ...[
                const SizedBox(width: 2),
                Icon(AppIcons.chevronRight, size: 12, color: muted),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            data.detail,
            style: theme.textTheme.labelSmall?.copyWith(
              color: data.pulse ? AppColors.critical : muted,
              fontSize: 10,
              height: 1.2,
              fontWeight: data.pulse ? FontWeight.w700 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (_pulse != null) {
      card = AnimatedBuilder(
        animation: _pulse!,
        builder: (_, child) {
          final glow = 0.25 + 0.55 * _pulse!.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: AppColors.critical.withOpacity(glow),
                  blurRadius: 14 + 6 * _pulse!.value,
                  spreadRadius: 0.5 + _pulse!.value,
                ),
              ],
            ),
            child: child,
          );
        },
        child: card,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: card,
      ),
    );
  }
}
