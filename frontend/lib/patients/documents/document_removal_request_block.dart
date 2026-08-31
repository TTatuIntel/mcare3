import 'package:flutter/material.dart';

import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

/// The patient's route to having a document taken out that they cannot delete.
///
/// Nothing a clinician files can be deleted by staff on their own say-so, which
/// is right, and until now was also the end of the conversation: a result filed
/// against the wrong person stayed attached to the person it was wrong about,
/// with no way to raise it and nothing recorded either way. Asking here is what
/// authorises a staff-side deletion at all — the request is the permission.
///
/// Deliberately not offered on an issued report. That is a disclosure the
/// patient consented to, and the record of it is the point; it is revoked, not
/// erased. The server refuses either way, and offering a control it would
/// refuse only teaches people the app is broken.
class DocumentRemovalRequestBlock extends StatefulWidget {
  const DocumentRemovalRequestBlock({
    super.key,
    required this.document,
    required this.onChanged,
  });

  final MedicalDocument document;
  final ValueChanged<MedicalDocument> onChanged;

  @override
  State<DocumentRemovalRequestBlock> createState() =>
      _DocumentRemovalRequestBlockState();
}

class _DocumentRemovalRequestBlockState
    extends State<DocumentRemovalRequestBlock> {
  bool _busy = false;

  MedicalDocument get _doc => widget.document;

  Future<void> _ask() async {
    final reason = await _promptReason(context);
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final saved = await DocumentsState.instance.requestRemoval(
        id: _doc.id,
        reason: reason,
      );
      if (!mounted) return;
      widget.onChanged(saved);
      AppToast.success(
        context,
        'Your care team has been asked to remove this document.',
      );
    } catch (e) {
      if (mounted) AppToast.warn(context, 'Could not send the request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      final saved = await DocumentsState.instance.cancelRemovalRequest(_doc.id);
      if (!mounted) return;
      widget.onChanged(saved);
      AppToast.info(context, 'Removal request withdrawn.');
    } catch (e) {
      if (mounted) AppToast.warn(context, 'Could not withdraw: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;

    if (doc.removalRequested) {
      return _Notice(
        icon: AppIcons.time,
        color: AppColors.warning,
        title: 'Removal requested',
        message: doc.removalReason == null
            ? 'Your care team has been asked to remove this document and will '
                  'reply here.'
            : 'You asked for this to be removed: “${doc.removalReason}”. Your '
                  'care team will reply here.',
        action: AppButton(
          label: 'Withdraw the request',
          icon: AppIcons.close,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          expand: true,
          loading: _busy,
          onPressed: _busy ? null : _withdraw,
        ),
      );
    }

    // A refusal is an answer, not a dead end — the patient can read the reason
    // and ask again with what it missed.
    if (doc.removalDeclinedReason != null) {
      return _Notice(
        icon: AppIcons.info,
        color: AppColors.critical,
        title: 'Removal declined',
        message: 'Your care team kept this document. '
            '“${doc.removalDeclinedReason}”',
        action: doc.canRequestRemoval
            ? AppButton(
                label: 'Ask again',
                icon: AppIcons.send,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                expand: true,
                loading: _busy,
                onPressed: _busy ? null : _ask,
              )
            : null,
      );
    }

    if (!doc.canRequestRemoval) return const SizedBox.shrink();

    return _Notice(
      icon: AppIcons.lock,
      color: AppColors.brandIndigo,
      title: 'Filed by your care team',
      message:
          'This is part of your clinical record, so you cannot delete it '
          'yourself. If it should not be here — it is not yours, or the details '
          'are wrong — ask your care team to take it out.',
      action: AppButton(
        label: 'Ask for this to be removed',
        icon: AppIcons.send,
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.sm,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : _ask,
      ),
    );
  }
}

/// The reason is not optional: staff are being asked to make the one deletion
/// the record allows, and "they asked" is not enough to act on.
Future<String?> _promptReason(BuildContext context) {
  final controller = TextEditingController();

  return GlassSheet.show<String>(
    context,
    title: 'Ask for this to be removed',
    subtitle: 'Your care team decides, and replies here either way.',
    child: StatefulBuilder(
      builder: (context, setState) {
        final valid = controller.text.trim().length >= 4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell them what is wrong with it — for example that it belongs '
              'to someone else, or that the details do not match you.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Why should this be removed?',
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 280,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Send the request',
              icon: AppIcons.send,
              expand: true,
              onPressed: valid
                  ? () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(controller.text.trim())
                  : null,
            ),
          ],
        );
      },
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
