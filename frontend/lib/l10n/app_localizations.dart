import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_language.dart';
import 'app_strings.dart';

/// App-wide localized strings with real-time locale switching.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static List<Locale> get supportedLocales =>
      AppLanguage.all.map((l) => l.locale).toList();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static AppLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  String _t(String key) {
    final table = kAppStrings[locale.languageCode] ?? kAppStrings['en']!;
    return table[key] ?? kAppStrings['en']![key] ?? key;
  }

  String get settings => _t('settings');
  String get settingsSubtitle => _t('settingsSubtitle');
  String get appearance => _t('appearance');
  String get theme => _t('theme');
  String get themeLight => _t('themeLight');
  String get themeDark => _t('themeDark');
  String get themeSystem => _t('themeSystem');
  String get language => _t('language');
  String get languageSet => _t('languageSet');
  String get notifications => _t('notifications');
  String get privacy => _t('privacy');
  String get profile => _t('profile');
  String get alerts => _t('alerts');
  String get allNotifications => _t('allNotifications');
  String get allNotificationsSub => _t('allNotificationsSub');
  String get saveChanges => _t('saveChanges');
  String get editAccount => _t('editAccount');
  String get editAccountSub => _t('editAccountSub');
  String get firstName => _t('firstName');
  String get lastName => _t('lastName');
  String get mobilePhone => _t('mobilePhone');
  String get nameRequired => _t('nameRequired');
  String get phoneInvalid => _t('phoneInvalid');
  String get accountUpdated => _t('accountUpdated');
  String get themeSet => _t('themeSet');
  String get chooseLanguage => _t('chooseLanguage');
  String get searchLanguages => _t('searchLanguages');
  String get close => _t('close');
  String get shareWithCareTeam => _t('shareWithCareTeam');
  String get allowExternalAccess => _t('allowExternalAccess');

  String themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => themeLight,
    ThemeMode.dark => themeDark,
    ThemeMode.system => themeSystem,
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.all.any((l) => l.code == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
