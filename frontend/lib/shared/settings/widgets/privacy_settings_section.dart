import 'package:flutter/material.dart';

import '../../state/settings_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/patient_page_blocks.dart';

/// Privacy toggles shared by patient and doctor settings.
class PrivacySettingsSection extends StatelessWidget {
  const PrivacySettingsSection({super.key, this.sectionKey});

  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    final s = SettingsState.instance;

    return KeyedSubtree(
      key: sectionKey,
      child: GlassCard(
        frosted: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          children: [
            PatientCompactToggleRow(
              label: 'Share chart edits with care team',
              subtitle: 'Other clinicians see when you update a record',
              value: s.privacyShareWithCareTeam,
              onChanged: (v) {
                s.setPrivacyShareWithCareTeam(v);
                AppToast.success(
                  context,
                  v ? 'Care team sharing enabled' : 'Care team sharing disabled',
                );
              },
            ),
            PatientCompactToggleRow(
              label: 'Allow external doctor handoff',
              subtitle: 'Time-limited tokens for consults outside the org',
              value: s.privacyAllowExternalAccess,
              onChanged: (v) {
                s.setPrivacyAllowExternalAccess(v);
                AppToast.success(
                  context,
                  v ? 'External access allowed' : 'External access blocked',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
