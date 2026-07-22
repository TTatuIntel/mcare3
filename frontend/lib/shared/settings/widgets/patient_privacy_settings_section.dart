import 'package:flutter/material.dart';

import '../../auth/auth_state.dart';
import '../../services/profile_service.dart';
import '../../state/profile_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/patient_page_blocks.dart';

/// Patient-only privacy toggles including SOS location consent.
///
/// Pass [onManageExternalAccess] from the patient settings screen to open the
/// create/share external-link sheet (keeps `shared/` free of role imports).
class PatientPrivacySettingsSection extends StatelessWidget {
  const PatientPrivacySettingsSection({
    super.key,
    this.sectionKey,
    this.onManageExternalAccess,
  });

  final Key? sectionKey;
  final VoidCallback? onManageExternalAccess;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsState.instance;
    final user = AuthState.instance.user;

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
              label: 'Share data with care team',
              subtitle: 'Assigned providers can view your records',
              value: settings.privacyShareWithCareTeam,
              onChanged: settings.setPrivacyShareWithCareTeam,
            ),
            PatientCompactToggleRow(
              label: 'External doctor access',
              subtitle: 'Allow time-limited links for outside clinicians',
              value: settings.privacyAllowExternalAccess,
              onChanged: settings.setPrivacyAllowExternalAccess,
            ),
            if (settings.privacyAllowExternalAccess &&
                onManageExternalAccess != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Create & share external link',
                icon: AppIcons.link,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: onManageExternalAccess,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Outside doctors can open the link on the web to record '
                'vitals, assign medication, and upload documents/reports.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            PatientCompactToggleRow(
              label: 'Location consent (SOS)',
              subtitle: 'Share GPS during emergencies',
              value: ProfileState.instance.health?.locationConsent ?? false,
              onChanged: user == null
                  ? (_) {}
                  : (v) => ProfileService.setLocationConsent(
                        editor: user,
                        value: v,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
