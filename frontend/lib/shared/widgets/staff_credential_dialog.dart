import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'app_toast.dart';

/// A single labelled secret shown in [showStaffCredentialDialog].
class StaffCredentialValue {
  const StaffCredentialValue({required this.label, required this.value});

  final String label;
  final String value;
}

/// Barrier-dismissible-off dialog used across staff directories to surface a
/// one-shot temporary password, invite token, or similar credential. Values
/// render as copy-only cards so operators can hand them off cleanly.
Future<void> showStaffCredentialDialog(
  BuildContext context, {
  required String title,
  required String message,
  required List<StaffCredentialValue> values,
  IconData icon = AppIcons.lock,
  String? statusMessage,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      backgroundColor: AppPalette.surface(dialogContext),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: AppPalette.border(dialogContext)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppPalette.infoSoft(dialogContext),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Icon(icon, color: AppColors.info, size: 26),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: Theme.of(dialogContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textMuted(dialogContext),
                    ),
              ),
              if (statusMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppPalette.successSoft(dialogContext),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        AppIcons.check,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              for (var index = 0; index < values.length; index++) ...[
                _StaffCredentialCard(value: values[index]),
                if (index != values.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Done',
                expand: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StaffCredentialCard extends StatelessWidget {
  const _StaffCredentialCard({required this.value});

  final StaffCredentialValue value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  value.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                ),
              ),
              IconButton(
                tooltip: hasValue ? 'Copy ${value.label}' : 'Nothing to copy',
                visualDensity: VisualDensity.compact,
                onPressed: hasValue
                    ? () async {
                        await Clipboard.setData(
                          ClipboardData(text: value.value),
                        );
                        if (context.mounted) {
                          AppToast.success(context, '${value.label} copied');
                        }
                      }
                    : null,
                icon: const Icon(AppIcons.copy, size: 18),
              ),
            ],
          ),
          SelectableText(
            hasValue ? value.value : '(not returned — retry)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: hasValue ? 1.1 : 0,
                ),
          ),
        ],
      ),
    );
  }
}
