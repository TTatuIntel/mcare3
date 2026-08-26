import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api/settings_api.dart';
import '../../core/env/app_env.dart';
import '../../l10n/app_language.dart';
import '../models/patient_profile.dart';
import '../services/settings_storage.dart';

class SettingsState extends ChangeNotifier {
  SettingsState._();
  static final SettingsState instance = SettingsState._();

  ThemeMode _themeMode = ThemeMode.light;
  NotificationPreferences _notifications = NotificationPreferences();
  String _languageCode = AppLanguage.defaultCode;
  bool _privacyShareWithCareTeam = true;
  bool _privacyAllowExternalAccess = false;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  NotificationPreferences get notifications => _notifications;
  String get languageCode => _languageCode;
  AppLanguage get currentLanguage => AppLanguage.byCode(_languageCode);

  /// Display name for hero tiles (native script when available).
  String get language => currentLanguage.nativeName;
  bool get privacyShareWithCareTeam => _privacyShareWithCareTeam;
  bool get privacyAllowExternalAccess => _privacyAllowExternalAccess;
  bool get isLoaded => _loaded;

  Locale get locale => currentLanguage.locale;

  int get enabledNotificationCount =>
      _notifications.channelValues.where((v) => v).length;

  bool get allNotificationsOn => _notifications.channelValues.every((v) => v);

  int get patientNotificationChannelCount => 7;

  int get patientEnabledNotificationCount => [
    _notifications.vitalAlerts,
    _notifications.appointmentReminders,
    _notifications.medicationReminders,
    _notifications.messages,
    _notifications.pushEnabled,
    _notifications.smsEnabled,
    _notifications.emailEnabled,
  ].where((v) => v).length;

  bool get allPatientNotificationsOn => patientEnabledNotificationCount == 7;

  int get doctorNotificationChannelCount => 6;

  int get doctorEnabledNotificationCount => [
    _notifications.vitalAlerts,
    _notifications.appointmentReminders,
    _notifications.messages,
    _notifications.reports,
    _notifications.pushEnabled,
    _notifications.emailEnabled,
  ].where((v) => v).length;

  bool get allDoctorNotificationsOn => doctorEnabledNotificationCount == 6;

  int get adminNotificationChannelCount => 7;

  /// Admin ops alerts — reuses persisted notification channels with admin labels.
  int get adminEnabledNotificationCount => [
    _notifications.vitalAlerts,
    _notifications.medicationReminders,
    _notifications.appointmentReminders,
    _notifications.reports,
    _notifications.messages,
    _notifications.pushEnabled,
    _notifications.emailEnabled,
  ].where((v) => v).length;

  bool get allAdminNotificationsOn =>
      adminEnabledNotificationCount == adminNotificationChannelCount;

  Future<void> loadPersisted() async {
    final data = await SettingsStorage.readAll();
    if (data != null) {
      applyPersisted(
        themeMode: data['themeMode'] as ThemeMode?,
        languageCode: data['languageCode'] as String?,
        notifications: data['notifications'] as NotificationPreferences?,
        privacyShareWithCareTeam: data['privacyShareWithCareTeam'] as bool?,
        privacyAllowExternalAccess: data['privacyAllowExternalAccess'] as bool?,
      );
    }
    _loaded = true;
    notifyListeners();
  }

  /// Pull the signed-in user's preferences from the backend and apply them.
  ///
  /// Called after authentication (settings load at startup happens before a
  /// token exists). The server payload is authoritative when present; results
  /// are also cached to local storage so the next cold start paints correctly
  /// before this round-trip completes. Safe to call for any role; no-op when
  /// the backend is disabled or the request fails.
  Future<void> pullRemote() async {
    if (!AppEnv.backendEnabled) return;
    try {
      final data = await SettingsApi.instance.fetch();
      if (data == null || data.isEmpty) return;

      final notifRaw = data['notifications'];
      applyPersisted(
        themeMode: _themeFromString(data['theme_mode'] as String?),
        languageCode: data['language_code'] as String?,
        notifications: notifRaw is Map
            ? NotificationPreferences.fromJson(
                Map<String, dynamic>.from(notifRaw),
              )
            : null,
        privacyShareWithCareTeam: data['privacy_share_with_care_team'] as bool?,
        privacyAllowExternalAccess:
            data['privacy_allow_external_access'] as bool?,
      );
      _loaded = true;
      notifyListeners();
      _cacheLocal();
    } catch (_) {
      // Non-fatal — keep whatever local/default settings are already applied.
    }
  }

  void applyPersisted({
    ThemeMode? themeMode,
    String? languageCode,
    NotificationPreferences? notifications,
    bool? privacyShareWithCareTeam,
    bool? privacyAllowExternalAccess,
  }) {
    if (themeMode != null) _themeMode = themeMode;
    if (languageCode != null) {
      _languageCode = AppLanguage.byCode(languageCode).code;
    }
    if (notifications != null) _notifications = notifications;
    if (privacyShareWithCareTeam != null) {
      _privacyShareWithCareTeam = privacyShareWithCareTeam;
    }
    if (privacyAllowExternalAccess != null) {
      _privacyAllowExternalAccess = privacyAllowExternalAccess;
    }
  }

  void seed({
    ThemeMode? themeMode,
    NotificationPreferences? notifications,
    String? languageCode,
  }) {
    if (themeMode != null) _themeMode = themeMode;
    if (notifications != null) _notifications = notifications;
    if (languageCode != null) {
      _languageCode = AppLanguage.byCode(languageCode).code;
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _persist();
  }

  void setLanguageCode(String code) {
    final normalized = AppLanguage.byCode(code).code;
    if (_languageCode == normalized) return;
    _languageCode = normalized;
    notifyListeners();
    _persist();
  }

  /// @deprecated Use [setLanguageCode].
  void setLanguage(String lang) => setLanguageCode(lang);

  void setPrivacyShareWithCareTeam(bool value) {
    if (_privacyShareWithCareTeam == value) return;
    _privacyShareWithCareTeam = value;
    notifyListeners();
    _persist();
  }

  void setPrivacyAllowExternalAccess(bool value) {
    if (_privacyAllowExternalAccess == value) return;
    _privacyAllowExternalAccess = value;
    notifyListeners();
    _persist();
  }

  void setAllPatientNotifications(bool enabled) {
    _notifications = _notifications.copyWith(
      vitalAlerts: enabled,
      appointmentReminders: enabled,
      medicationReminders: enabled,
      messages: enabled,
      pushEnabled: enabled,
      smsEnabled: enabled,
      emailEnabled: enabled,
    );
    notifyListeners();
    _persist();
  }

  void setAllDoctorNotifications(bool enabled) {
    _notifications = _notifications.copyWith(
      vitalAlerts: enabled,
      appointmentReminders: enabled,
      messages: enabled,
      reports: enabled,
      pushEnabled: enabled,
      emailEnabled: enabled,
    );
    notifyListeners();
    _persist();
  }

  void setAllAdminNotifications(bool enabled) {
    _notifications = _notifications.copyWith(
      vitalAlerts: enabled,
      medicationReminders: enabled,
      appointmentReminders: enabled,
      reports: enabled,
      messages: enabled,
      pushEnabled: enabled,
      emailEnabled: enabled,
    );
    notifyListeners();
    _persist();
  }

  void toggleNotification(String key, bool value) {
    switch (key) {
      case 'vitalAlerts':
        _notifications.vitalAlerts = value;
      case 'appointmentReminders':
        _notifications.appointmentReminders = value;
      case 'medicationReminders':
        _notifications.medicationReminders = value;
      case 'messages':
        _notifications.messages = value;
      case 'reports':
        _notifications.reports = value;
      case 'pushEnabled':
        _notifications.pushEnabled = value;
      case 'smsEnabled':
        _notifications.smsEnabled = value;
      case 'emailEnabled':
        _notifications.emailEnabled = value;
    }
    notifyListeners();
    _persist();
  }

  void _persist() {
    _cacheLocal();
    if (AppEnv.backendEnabled) {
      unawaited(SettingsApi.instance.save(_remotePayload()));
    }
  }

  void _cacheLocal() {
    unawaited(
      SettingsStorage.writeAll(
        themeMode: _themeMode,
        languageCode: _languageCode,
        notifications: _notifications,
        privacyShareWithCareTeam: _privacyShareWithCareTeam,
        privacyAllowExternalAccess: _privacyAllowExternalAccess,
      ),
    );
  }

  Map<String, dynamic> _remotePayload() => {
    'theme_mode': _themeToString(_themeMode),
    'language_code': _languageCode,
    'notifications': _notifications.toJson(),
    'privacy_share_with_care_team': _privacyShareWithCareTeam,
    'privacy_allow_external_access': _privacyAllowExternalAccess,
  };

  static String _themeToString(ThemeMode mode) => switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
  };

  static ThemeMode? _themeFromString(String? raw) => switch (raw) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    _ => null,
  };
}
