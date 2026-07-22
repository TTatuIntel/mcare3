import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/language_picker.dart';
import 'settings_dropdown_row.dart';

/// Theme + language block shared by patient, doctor, and admin settings.
class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key, this.sectionKey});

  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            SettingsDropdownRow<ThemeMode>(
              label: l10n.theme,
              subtitle: l10n.themeLabel(s.themeMode),
              value: s.themeMode,
              items: [
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(l10n.themeLight),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(l10n.themeDark),
                ),
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(l10n.themeSystem),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                s.setThemeMode(v);
                AppToast.success(
                  context,
                  '${l10n.themeSet} ${l10n.themeLabel(v)}',
                );
              },
            ),
            Divider(height: 1, color: AppPalette.border(context)),
            const LanguagePickerRow(),
          ],
        ),
      ),
    );
  }
}
