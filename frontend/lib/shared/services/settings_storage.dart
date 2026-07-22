import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/web/web_platform.dart' as web_platform;
import '../models/patient_profile.dart';
import '../../l10n/app_language.dart';

/// Persists user settings locally (theme, language, notifications, privacy).
class SettingsStorage {
  SettingsStorage._();

  static const _keyTheme = 'mcare_theme_mode';
  static const _keyLanguage = 'mcare_language';
  static const _keyNotifications = 'mcare_notifications';
  static const _keyPrivacyShare = 'mcare_privacy_share_care_team';
  static const _keyPrivacyExternal = 'mcare_privacy_external_access';

  static String? _read(String key) => web_platform.localStorageGet(key);

  static void _write(String key, String value) =>
      web_platform.localStorageSet(key, value);

  static bool _has(String key) => _read(key) != null;

  static Future<Map<String, dynamic>?> readAll() async {
    if (!_has(_keyTheme) &&
        !_has(_keyLanguage) &&
        !_has(_keyNotifications)) {
      return null;
    }

    NotificationPreferences? notifications;
    final notifRaw = _read(_keyNotifications);
    if (notifRaw != null) {
      try {
        notifications = NotificationPreferences.fromJson(
          jsonDecode(notifRaw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    final shareRaw = _read(_keyPrivacyShare);
    final externalRaw = _read(_keyPrivacyExternal);

    return {
      'themeMode': _parseTheme(_read(_keyTheme)),
      'languageCode': AppLanguage.byCode(_read(_keyLanguage)).code,
      'notifications': notifications,
      'privacyShareWithCareTeam': shareRaw == null ? true : shareRaw == 'true',
      'privacyAllowExternalAccess':
          externalRaw == null ? false : externalRaw == 'true',
    };
  }

  static Future<void> writeAll({
    required ThemeMode themeMode,
    required String languageCode,
    required NotificationPreferences notifications,
    required bool privacyShareWithCareTeam,
    required bool privacyAllowExternalAccess,
  }) async {
    _write(_keyTheme, _themeToString(themeMode));
    _write(_keyLanguage, AppLanguage.byCode(languageCode).code);
    _write(_keyNotifications, jsonEncode(notifications.toJson()));
    _write(_keyPrivacyShare, privacyShareWithCareTeam.toString());
    _write(_keyPrivacyExternal, privacyAllowExternalAccess.toString());
  }

  static ThemeMode _parseTheme(String? raw) => switch (raw) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  static String _themeToString(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };
}
