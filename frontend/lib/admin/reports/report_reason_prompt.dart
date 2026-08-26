import 'package:flutter/material.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Captures a free-text reason before a decision that gets audited.
///
/// Every revoke / decline on the report workflow must carry a reason, and the
/// backend enforces a 4-character minimum, so the sheet blocks submission
/// until there is something worth recording.
Future<String?> promptReason(
  BuildContext context, {
  required String title,
  required String message,
  String label = 'Reason',
  String confirmLabel = 'Confirm',
}) {
  final controller = TextEditingController();

  return GlassSheet.show<String>(
    context,
    title: title,
    subtitle: message,
    child: StatefulBuilder(
      builder: (context, setState) {
        final valid = controller.text.trim().length >= 4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: label,
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 280,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: confirmLabel,
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
