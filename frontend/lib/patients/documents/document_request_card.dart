import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/document.dart';
import '../../shared/models/document_request.dart';
import '../../shared/state/document_requests_state.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/request_activity_trail.dart';
import 'document_viewer_sheet.dart';

/// A document the patient has asked for and is still waiting on.
///
/// Kept visually distinct from a filed document: it is not something they can
/// open, and a row that looked like one would be a promise the record cannot
/// keep. What it does show is who has it and what has happened to it, which is
/// the question a bare "pending" chip never answers.
class DocumentRequestCard extends StatelessWidget {
  const DocumentRequestCard({super.key, required this.request});

  final DocumentRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.status;

    return GlassCard(
      frosted: true,
      onTap: () => DocumentRequestDetailSheet.show(context, request),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(status.icon, size: 20, color: status.color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  request.statusLine,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(label: status.label, color: status.color),
                    _Pill(
                      label: request.category.label,
                      color: request.category.color,
                    ),
                    if (request.overdue)
                      _Pill(label: 'Overdue', color: AppColors.critical)
                    else if (request.neededBy != null && request.isOpen)
                      _Pill(
                        label:
                            'By ${DateFormat.MMMd().format(request.neededBy!)}',
                        color: AppColors.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            AppIcons.chevronRight,
            size: 18,
            color: AppPalette.textMuted(context),
          ),
        ],
      ),
    );
  }
}

class DocumentRequestDetailSheet extends StatelessWidget {
  const DocumentRequestDetailSheet({super.key, required this.request});

  final DocumentRequest request;

  static Future<void> show(BuildContext context, DocumentRequest request) {
    return GlassSheet.show<void>(
      context,
      title: request.title,
      subtitle: 'Document request',
      child: DocumentRequestDetailSheet(request: request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusBanner(request: request),
        const SizedBox(height: AppSpacing.md),

        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaRow(label: 'Type', value: request.category.label),
              _MetaRow(
                label: 'Asked',
                value: request.targetDoctorName == null
                    ? 'Your care team'
                    : '${request.targetDoctorName} · care team can see it too',
              ),
              _MetaRow(label: 'Raised', value: fmt.format(request.createdAt)),
              if (request.neededBy != null)
                _MetaRow(
                  label: 'Needed by',
                  value: fmt.format(request.neededBy!),
                ),
              if (request.note != null && request.note!.isNotEmpty)
                _MetaRow(label: 'Your note', value: request.note!),
              if (request.resolutionNote != null &&
                  request.resolutionNote!.isNotEmpty)
                _MetaRow(label: 'Their note', value: request.resolutionNote!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // The document, once there is one. Opening it from here saves the
        // patient hunting for it in a list they were just told to check.
        if (request.documentId != null) ...[
          AppButton(
            label: 'Open the document',
            icon: AppIcons.document,
            expand: true,
            onPressed: () => _openDocument(context),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        Text(
          'What has happened',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RequestActivityTrail(
          events: request.events,
          emptyMessage: 'Your care team has not opened this yet.',
        ),

        if (request.isOpen) ...[
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Withdraw request',
            icon: AppIcons.close,
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: () => _withdraw(context),
          ),
        ],
      ],
    );
  }

  void _openDocument(BuildContext context) {
    final doc = DocumentsState.instance.all
        .where((d) => d.id == request.documentId)
        .firstOrNull;
    if (doc == null) {
      // The request knows the document exists before the list has caught up.
      // Saying so beats opening an empty viewer.
      AppToast.info(context, 'Pull down on Documents to load it.');
      return;
    }
    Navigator.of(context).pop();
    DocumentViewerSheet.show(context, doc);
  }

  Future<void> _withdraw(BuildContext context) async {
    final messenger = Navigator.of(context);
    try {
      await DocumentRequestsState.instance.cancel(request.id);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.warn(context, 'Could not withdraw: $e');
      return;
    }
    if (!context.mounted) return;
    messenger.pop();
    AppToast.success(context, 'Request withdrawn.');
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.request});
  final DocumentRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.status;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, size: 18, color: status.color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: status.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // A decline reason is the whole message when there is one:
                  // being told no without being told why is what sends people
                  // back to the phone.
                  request.declineReason ?? request.statusLine,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
