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
  String _socketUrl = '';
  String _socketAppKey = '';
  bool? _serverSocketEnabled;
  Duration _pulseInterval = const Duration(seconds: 3);
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

  // ---------- Real-time delivery -----------------------------------------
  //
  // Same reasoning as the OAuth IDs, with sharper consequences. The socket
  // endpoint used to arrive only through `--dart-define`, so a build launched
  // without the flags had no live connection at all and quietly degraded to
  // polling — which is what made alerts and updates feel like they needed a
  // refresh. The API knows where its own broadcaster listens, so it says, and
  // a build that pinned an endpoint still wins.

  /// WebSocket endpoint (`ws://host:port`), empty when this deployment runs
  /// no socket server. Then the app relies on the pulse cursor alone, which
  /// needs no extra process to be running.
  String get socketUrl => AppEnv.wsUrl.isNotEmpty ? AppEnv.wsUrl : _socketUrl;

  /// The broadcaster's public app key — the Pusher-protocol handshake needs
  /// it. The secret stays on the server and is never published.
  String get socketAppKey =>
      AppEnv.wsAppKey.isNotEmpty ? AppEnv.wsAppKey : _socketAppKey;

  /// True when a live socket can be attempted at all.
  bool get socketEnabled =>
      AppEnv.backendEnabled &&
      _serverSocketEnabled != false &&
      socketUrl.isNotEmpty &&
      socketAppKey.isNotEmpty;

  /// How often to ask the server what changed while no socket is carrying
  /// events. The server names the cadence so it can be tuned per deployment
  /// without shipping a new build.
  Duration get pulseInterval => _pulseInterval;

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
      _applyRealtime(data['realtime'] as Map<String, dynamic>?);
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

  void _applyRealtime(Map<String, dynamic>? realtime) {
    if (realtime == null) return;

    final socket = realtime['socket'] as Map<String, dynamic>?;
    _serverSocketEnabled = socket?['enabled'] == true;
    if (socket != null && socket['enabled'] == true) {
      _socketUrl = (socket['url'] ?? '').toString().trim();
      _socketAppKey = (socket['key'] ?? '').toString().trim();
    } else {
      _socketUrl = '';
      _socketAppKey = '';
    }

    final pulse = realtime['pulse'] as Map<String, dynamic>?;
    final ms = int.tryParse('${pulse?['interval_ms'] ?? ''}');
    if (ms != null && ms > 0) {
      // Clamped: a server misconfiguration should not be able to hammer
      // itself from every client, nor stall live updates to a crawl.
      _pulseInterval = Duration(milliseconds: ms.clamp(1000, 30000));
    }
  }

  @visibleForTesting
  void applyForTesting({
    String googleClientId = '',
    String appleClientId = '',
    String appleRedirectUri = '',
    String socketUrl = '',
    String socketAppKey = '',
    bool? serverSocketEnabled,
    Duration pulseInterval = const Duration(seconds: 3),
  }) {
    _googleClientId = googleClientId;
    _appleClientId = appleClientId;
    _appleRedirectUri = appleRedirectUri;
    _socketUrl = socketUrl;
    _socketAppKey = socketAppKey;
    _serverSocketEnabled =
        serverSocketEnabled ??
        (socketUrl.isNotEmpty && socketAppKey.isNotEmpty ? true : null);
    _pulseInterval = pulseInterval;
    _loaded = true;
  }

  @visibleForTesting
  void resetForTesting() {
    _googleClientId = '';
    _appleClientId = '';
    _appleRedirectUri = '';
    _socketUrl = '';
    _socketAppKey = '';
    _serverSocketEnabled = null;
    _pulseInterval = const Duration(seconds: 3);
    _loaded = false;
  }
}
