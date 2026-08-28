import 'package:flutter/foundation.dart';

/// Compile-time environment flags. Production and normal local development
/// use the Laravel API; the legacy in-memory fixtures require explicit opt-in.
class AppEnv {
  AppEnv._();

  /// Disable only for isolated widget development. Disabling the backend no
  /// longer activates fixture data by itself.
  static const bool backendEnabled = bool.fromEnvironment(
    'MCARE_USE_BACKEND',
    defaultValue: true,
  );

  /// Legacy in-memory fixtures are retained for isolated UI development and
  /// tests, but never activate accidentally when the API is unavailable.
  static const bool demoDataEnabled = bool.fromEnvironment(
    'MCARE_ALLOW_DEMO_DATA',
    defaultValue: false,
  );

  static const String _rawApiBaseUrl = String.fromEnvironment(
    'MCARE_API_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// True when the caller explicitly passed `--dart-define=MCARE_API_URL=...`.
  /// If so, we respect the URL verbatim and skip the Android loopback rewrite.
  static const bool _apiUrlOverridden = bool.hasEnvironment('MCARE_API_URL');

  /// Base URL of the Laravel API. On the Android emulator, `127.0.0.1` refers
  /// to the emulator itself — `10.0.2.2` is the alias for the host machine's
  /// loopback. We rewrite it here so a fresh clone runs against a local
  /// backend without extra configuration. Physical devices still need a LAN
  /// IP via `--dart-define=MCARE_API_URL=http://<host>:8000/api/v1`.
  static final String apiBaseUrl = _resolveApiBaseUrl();

  static String _resolveApiBaseUrl() {
    if (_apiUrlOverridden || kIsWeb) return _rawApiBaseUrl;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _rawApiBaseUrl
          .replaceFirst('://127.0.0.1', '://10.0.2.2')
          .replaceFirst('://localhost', '://10.0.2.2');
    }
    return _rawApiBaseUrl;
  }

  /// Reverb (WebSocket) endpoint — set via
  ///   `--dart-define=MCARE_WS_URL=ws://127.0.0.1:8080`
  /// Empty by default so realtime is opt-in; when empty the app falls back
  /// to REST polling only (§7.1 fallback strategy).
  static const String _rawWsUrl = String.fromEnvironment(
    'MCARE_WS_URL',
    defaultValue: '',
  );

  static const bool _wsUrlOverridden = bool.hasEnvironment('MCARE_WS_URL');

  /// Rewrites localhost for the Android emulator exactly as the REST base URL
  /// does, while respecting an explicitly supplied device/LAN endpoint.
  static final String wsUrl = _resolveWsUrl();

  static String _resolveWsUrl() {
    if (_rawWsUrl.isEmpty || _wsUrlOverridden || kIsWeb) return _rawWsUrl;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _rawWsUrl
          .replaceFirst('://127.0.0.1', '://10.0.2.2')
          .replaceFirst('://localhost', '://10.0.2.2');
    }
    return _rawWsUrl;
  }

  /// The Reverb `app_key` from backend/.env `REVERB_APP_KEY`. Required to
  /// establish a Pusher-protocol handshake with the Reverb server.
  static const String wsAppKey = String.fromEnvironment(
    'MCARE_WS_APP_KEY',
    defaultValue: '',
  );

  static bool get realtimeEnabled =>
      backendEnabled && wsUrl.isNotEmpty && wsAppKey.isNotEmpty;

  /// Google OAuth web client ID — set via `--dart-define=MCARE_GOOGLE_CLIENT_ID=...`
  /// or use the default mCare web client for local development.
  static const String googleClientId = String.fromEnvironment(
    'MCARE_GOOGLE_CLIENT_ID',
    defaultValue:
        '937360649671-3fnpje16hqhamfpemih9k2kub8o9e3f2.apps.googleusercontent.com',
  );

  static bool get hasGoogleClientId => googleClientId.isNotEmpty;

  /// Web OAuth client ID used as the native server client ID so Google issues
  /// an ID token whose audience the Laravel API can verify.
  static const String googleServerClientId = String.fromEnvironment(
    'MCARE_GOOGLE_SERVER_CLIENT_ID',
    defaultValue: googleClientId,
  );

  /// iOS OAuth client ID. Android derives its application identity from the
  /// package name/signing certificate and therefore does not use this value.
  static const String googleIosClientId = String.fromEnvironment(
    'MCARE_GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// Apple "Sign in with Apple" web Services ID —
  /// `--dart-define=MCARE_APPLE_CLIENT_ID=com.example.web`. Empty by default,
  /// which keeps Apple login unavailable until it is configured.
  static const String appleClientId = String.fromEnvironment(
    'MCARE_APPLE_CLIENT_ID',
    defaultValue: '',
  );

  /// Return URL registered with Apple for the web popup flow —
  /// `--dart-define=MCARE_APPLE_REDIRECT_URI=https://app.example.com/`.
  static const String appleRedirectUri = String.fromEnvironment(
    'MCARE_APPLE_REDIRECT_URI',
    defaultValue: '',
  );

  static bool get hasAppleClientId => appleClientId.isNotEmpty;

  static const Duration apiTimeout = Duration(seconds: 30);

  // ---------- Firebase (push notifications) -------------------------------
  static const String firebaseApiKey = String.fromEnvironment(
    'MCARE_FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const String firebaseAppId = String.fromEnvironment(
    'MCARE_FIREBASE_APP_ID',
    defaultValue: '',
  );
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'MCARE_FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'MCARE_FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  /// Web push VAPID key — Firebase Console → Project settings → Cloud Messaging
  static const String firebaseVapidKey = String.fromEnvironment(
    'MCARE_FIREBASE_VAPID_KEY',
    defaultValue: '',
  );

  static bool get firebaseEnabled =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty;
}
