import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'app_env.dart';

/// Public client configuration, resolved from the API at launch.
///
/// OAuth client IDs reach a Flutter build through `--dart-define`, which means
/// they are only present if whoever produced the build remembered the flag.
/// Every path that forgot it — a run script, a plain `flutter build web`, an
/// IDE launch profile — shipped an app that told users Google sign-in was
/// unavailable, and a path that passed the *wrong* ID shipped one whose tokens
/// the API rejected as an audience mismatch. Neither failure is visible until
/// somebody taps the button.
///
/// So the app asks the server it authenticates against. The server is the only
/// authority on which client ID it will accept, so the two cannot disagree,
/// and rotating a credential takes effect on reload instead of on rebuild.
///
/// A `--dart-define` still wins where one is given: native builds are signed
/// against a specific client and a release must be able to pin it without
/// depending on a network call.
class RuntimeConfig {
  RuntimeConfig._();

  static final RuntimeConfig instance = RuntimeConfig._();

  String _googleClientId = '';
  String _appleClientId = '';
  String _appleRedirectUri = '';
  bool _loaded = false;

  /// True once a response has been applied. Sign-in surfaces do not wait on
  /// this — a build with compile-time values is configured from the start.
  bool get isLoaded => _loaded;

  /// Compile-time value if the build pinned one, otherwise the server's.
  String get googleClientId => AppEnv.isConfiguredValue(AppEnv.googleClientId)
      ? AppEnv.googleClientId
      : _googleClientId;

  /// What Google should address the ID token to. Native builds ask for a token
  /// aimed at the *server* client so the API can verify it; when nothing is
  /// pinned that is the same value the API just told us it accepts.
  String get googleServerClientId =>
      AppEnv.configuredGoogleServerClientId.isNotEmpty
      ? AppEnv.configuredGoogleServerClientId
      : googleClientId;

  bool get hasGoogleClientId => AppEnv.isConfiguredValue(googleClientId);

  String get appleClientId => AppEnv.isConfiguredValue(AppEnv.appleClientId)
      ? AppEnv.appleClientId
      : _appleClientId;

  String get appleRedirectUri =>
      AppEnv.isConfiguredValue(AppEnv.appleRedirectUri)
      ? AppEnv.appleRedirectUri
      : _appleRedirectUri;

  bool get hasAppleClientId =>
      AppEnv.isConfiguredValue(appleClientId) &&
      AppEnv.isConfiguredValue(appleRedirectUri);

  /// Reads `/config`. Never throws and never blocks launch: an unreachable API
  /// leaves the app exactly as configured as its build made it.
  Future<void> load() async {
    if (!AppEnv.backendEnabled) return;

    try {
      final res = await ApiClient.instance
          .get('/config', allowWhenBackendDisabled: false)
          .timeout(const Duration(seconds: 6));
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final google = data['google'] as Map<String, dynamic>?;
      final apple = data['apple'] as Map<String, dynamic>?;

      _googleClientId = (google?['client_id'] ?? '').toString().trim();
      _appleClientId = (apple?['client_id'] ?? '').toString().trim();
      _appleRedirectUri = (apple?['redirect_uri'] ?? '').toString().trim();
      _loaded = true;

      if (kDebugMode && !hasGoogleClientId) {
        debugPrint(
          'mCare: the API reports no Google client ID, so Google sign-in '
          'stays unavailable. Set GOOGLE_CLIENT_ID in backend/.env.',
        );
      }
    } catch (_) {
      // Offline, or an older API without /config. Compile-time values, if the
      // build has any, still stand.
    }
  }

  @visibleForTesting
  void applyForTesting({
    String googleClientId = '',
    String appleClientId = '',
    String appleRedirectUri = '',
  }) {
    _googleClientId = googleClientId;
    _appleClientId = appleClientId;
    _appleRedirectUri = appleRedirectUri;
    _loaded = true;
  }

  @visibleForTesting
  void resetForTesting() {
    _googleClientId = '';
    _appleClientId = '';
    _appleRedirectUri = '';
    _loaded = false;
  }
}
