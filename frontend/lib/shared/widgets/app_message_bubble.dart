import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Single chat bubble used by every role's messaging UI.
class AppMessageBubble extends StatelessWidget {
  const AppMessageBubble({
    super.key,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.author,
  });

  final String body;
  final DateTime sentAt;
  final bool isMine;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm().format(sentAt);
    final accent = Theme.of(context).colorScheme.primary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? accent : AppPalette.surfaceAlt(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppSpacing.radiusMd),
            topRight: const Radius.circular(AppSpacing.radiusMd),
            bottomLeft: Radius.circular(isMine ? AppSpacing.radiusMd : 4),
            bottomRight: Radius.circular(isMine ? 4 : AppSpacing.radiusMd),
          ),
          border: isMine ? null : Border.all(color: AppPalette.border(context)),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (author != null && !isMine) ...[
              Text(author!, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
            ],
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isMine ? Colors.white : AppPalette.ink(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: isMine
                    ? Colors.white.withOpacity(0.75)
                    : AppPalette.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
