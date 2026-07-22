import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_blocks.dart';

/// One row in a staff "needs attention" feed.
class StaffAttentionItem {
  const StaffAttentionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.pill,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String pill;
  final VoidCallback onTap;
}

/// SectionLabel + empty state or StaffListCard — shared by admin/doctor dashboards.
class StaffAttentionSection extends StatelessWidget {
  const StaffAttentionSection({
    super.key,
    required this.title,
    required this.items,
    this.emptyMessage = 'Everything looks good — no items need attention.',
  });

  final String title;
  final List<StaffAttentionItem> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: title,
          icon: AppIcons.alert,
          trailing: items.isEmpty ? null : '${items.length}',
        ),
        items.isEmpty
            ? GlassCard(
                frosted: true,
                child: Row(
                  children: [
                    Icon(AppIcons.check, color: AppColors.success, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        emptyMessage,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            : StaffListCard(
                children: items
                    .map(
                      (item) => StaffListRow(
                        icon: item.icon,
                        iconColor: item.color,
                        title: item.title,
                        subtitle: item.subtitle,
                        pill: item.pill,
                        pillColor: item.color,
                        onTap: item.onTap,
                      ),
                    )
                    .toList(),
              ),
      ],
    );
  }
}
