import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/request_activity_event.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The life of a shared request, as a timeline.
///
/// Deliberately shown to patients as well as staff. A status chip can read
/// "waiting" for three days without ever answering the question the patient
/// actually has — is anyone looking at this? — and that unanswered question is
/// what turns into a phone call to the desk.
class RequestActivityTrail extends StatelessWidget {
  const RequestActivityTrail({
    super.key,
    required this.events,
    this.emptyMessage = 'Nothing has happened on this request yet.',
  });

  final List<RequestActivityEvent> events;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (events.isEmpty) {
      return Text(
        emptyMessage,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppPalette.textMuted(context),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < events.length; i++)
          _TrailRow(event: events[i], isLast: i == events.length - 1),
      ],
    );
  }
}

class _TrailRow extends StatelessWidget {
  const _TrailRow({required this.event, required this.isLast});

  final RequestActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.action.color;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: a dot per event, joined by a line that stops at the last one
          // so the timeline reads as finished rather than trailing off.
          Column(
            children: [
              Container(
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(event.action.icon, size: 13, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: AppPalette.border(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.sentence,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat.MMMd().add_jm().format(event.happenedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                  if (event.note != null && event.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppPalette.surfaceMuted(
                          context,
                        ).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Text(
                        event.note!,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
