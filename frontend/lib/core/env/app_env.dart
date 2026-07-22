/// Environment flags — flip [backendEnabled] when the Laravel API is live.
class AppEnv {
  AppEnv._();

  /// When false, all repositories read/write mock state only.
  /// Disable with: `--dart-define=MCARE_USE_BACKEND=false`
  static const bool backendEnabled = bool.fromEnvironment(
    'MCARE_USE_BACKEND',
    defaultValue: true,
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'MCARE_API_URL',
    defaultValue: 'http://127.0.0.1:9090/api/v1',
  );

  /// Google OAuth web client ID — set via `--dart-define=MCARE_GOOGLE_CLIENT_ID=...`
  /// or use the default mCare web client for local development.
  static const String googleClientId = String.fromEnvironment(
    'MCARE_GOOGLE_CLIENT_ID',
    defaultValue:
        '937360649671-3fnpje16hqhamfpemih9k2kub8o9e3f2.apps.googleusercontent.com',
  );

  static bool get hasGoogleClientId => googleClientId.isNotEmpty;

  /// Apple "Sign in with Apple" web Services ID —
  /// `--dart-define=MCARE_APPLE_CLIENT_ID=com.example.web`. Empty by default,
  /// which keeps Apple login in mock mode.
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
