import 'package:flutter/material.dart';

import '../models/vital.dart';
import '../theme/app_spacing.dart';

/// One risk badge — green/amber/red. Used on every vital surface.
class RiskBadge extends StatelessWidget {
  const RiskBadge({
    super.key,
    required this.risk,
    this.dense = false,
    this.label,
  });

  final RiskLevel risk;
  final bool dense;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: risk.softBg(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: risk.color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            width: 6,
            decoration:
                BoxDecoration(color: risk.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label ?? risk.label,
            style: TextStyle(
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: risk.labelColor(context),
            ),
          ),
        ],
      ),
    );
  }
}
