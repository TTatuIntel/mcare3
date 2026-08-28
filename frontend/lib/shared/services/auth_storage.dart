import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/web/web_platform.dart' as web_platform;

/// Stores remembered bearer tokens in platform secure storage. Short sessions
/// live only in browser sessionStorage / process memory and disappear when the
/// browser tab or native process closes.
class AuthStorage {
  AuthStorage._();

  static const _secure = FlutterSecureStorage();
  static const _keySession = 'mcare_auth_session_v2';
  static const _legacyToken = 'mcare_auth_token';
  static const _legacyUser = 'mcare_auth_user';
  static final Map<String, String> _secureFallback = <String, String>{};

  static Future<void> save({
    required String token,
    required Map<String, dynamic> user,
    bool hasHealthProfile = false,
    required bool remember,
    DateTime? expiresAt,
  }) async {
    final encoded = jsonEncode({
      'token': token,
      'user': user,
      'has_health_profile': hasHealthProfile,
      'remember': remember,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });

    if (remember) {
      web_platform.sessionStorageRemove(_keySession);
      await _secureWrite(_keySession, encoded);
    } else {
      await _secureDelete(_keySession);
      web_platform.sessionStorageSet(_keySession, encoded);
    }
    _clearLegacy();
  }

  static Future<
    ({
      String token,
      Map<String, dynamic> user,
      bool hasHealthProfile,
      bool remember,
      DateTime? expiresAt,
    })?
  >
  read() async {
    var raw = web_platform.sessionStorageGet(_keySession);
    var persistent = false;
    if (raw == null) {
      raw = await _secureRead(_keySession);
      persistent = raw != null;
    }

    // One-time compatibility import from the previous plain localStorage
    // format. The token is immediately moved into secure storage.
    if (raw == null) {
      final token = web_platform.localStorageGet(_legacyToken);
      final legacy = web_platform.localStorageGet(_legacyUser);
      if (token != null && legacy != null) {
        try {
          final decoded = jsonDecode(legacy) as Map<String, dynamic>;
          final user = Map<String, dynamic>.from(decoded['user'] as Map);
          await save(
            token: token,
            user: user,
            hasHealthProfile: decoded['has_health_profile'] == true,
            remember: true,
          );
          return (
            token: token,
            user: user,
            hasHealthProfile: decoded['has_health_profile'] == true,
            remember: true,
            expiresAt: null,
          );
        } catch (_) {
          _clearLegacy();
        }
      }
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final user = Map<String, dynamic>.from(decoded['user'] as Map);
      final expiresAt = DateTime.tryParse(
        decoded['expires_at']?.toString() ?? '',
      );
      if (expiresAt != null &&
          !expiresAt.toUtc().isAfter(DateTime.now().toUtc())) {
        await clear();
        return null;
      }
      return (
        token: decoded['token'] as String,
        user: user,
        hasHealthProfile: decoded['has_health_profile'] == true,
        remember: decoded['remember'] == true || persistent,
        expiresAt: expiresAt,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    web_platform.sessionStorageRemove(_keySession);
    await _secureDelete(_keySession);
    _clearLegacy();
  }

  static void _clearLegacy() {
    web_platform.localStorageRemove(_legacyToken);
    web_platform.localStorageRemove(_legacyUser);
  }

  static Future<String?> _secureRead(String key) async {
    try {
      return await _secure.read(key: key) ?? _secureFallback[key];
    } catch (_) {
      return _secureFallback[key];
    }
  }

  static Future<void> _secureWrite(String key, String value) async {
    _secureFallback[key] = value;
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {}
  }

  static Future<void> _secureDelete(String key) async {
    _secureFallback.remove(key);
    try {
      await _secure.delete(key: key);
    } catch (_) {}
  }
}
