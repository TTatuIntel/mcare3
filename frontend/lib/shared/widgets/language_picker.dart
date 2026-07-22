import 'package:flutter/material.dart';

import '../../l10n/app_language.dart';
import '../../l10n/app_localizations.dart';
import '../state/settings_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'app_toast.dart';
import 'glass_sheet.dart';

/// Opens a searchable language picker grouped by East African region.
class LanguagePickerSheet {
  LanguagePickerSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: context.l10n.chooseLanguage,
      subtitle: context.l10n.searchLanguages,
      maxHeightFactor: 0.85,
      child: const _LanguagePickerBody(),
    );
  }
}

class _LanguagePickerBody extends StatefulWidget {
  const _LanguagePickerBody();

  @override
  State<_LanguagePickerBody> createState() => _LanguagePickerBodyState();
}

class _LanguagePickerBodyState extends State<_LanguagePickerBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = SettingsState.instance.languageCode;
    final q = _query.trim().toLowerCase();

    final filtered = AppLanguage.all.where((lang) {
      if (q.isEmpty) return true;
      return lang.code.contains(q) ||
          lang.englishName.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q) ||
          lang.region.toLowerCase().contains(q);
    }).toList();

    final byRegion = <String, List<AppLanguage>>{};
    for (final lang in filtered) {
      byRegion.putIfAbsent(lang.region, () => []).add(lang);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l10n.searchLanguages,
            prefixIcon: const Icon(AppIcons.search, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.md),
        ...byRegion.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  entry.key,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              ...entry.value.map((lang) {
                final selected = lang.code == current;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selected ? AppIcons.check : AppIcons.language,
                    color: selected ? AppColors.brandIndigo : AppPalette.textMuted(context),
                    size: 20,
                  ),
                  title: Text(
                    lang.nativeName,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${lang.englishName} · ${lang.code.toUpperCase()}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  trailing: selected
                      ? const Icon(AppIcons.check, color: AppColors.success, size: 18)
                      : null,
                  onTap: () {
                    SettingsState.instance.setLanguageCode(lang.code);
                    AppToast.success(context, l10n.languageSet);
                    Navigator.of(context).pop();
                  },
                );
              }),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        }),
      ],
    );
  }
}

/// Compact row that opens [LanguagePickerSheet].
class LanguagePickerRow extends StatelessWidget {
  const LanguagePickerRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = SettingsState.instance.currentLanguage;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        l10n.language,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        '${lang.nativeName} · ${lang.region}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
      ),
      trailing: const Icon(AppIcons.chevronRight, size: 18),
      onTap: () => LanguagePickerSheet.show(context),
    );
  }
}
