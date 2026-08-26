import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'core/env/app_env.dart';

/// Firebase options from `--dart-define` values (see AppEnv).
/// Run `flutterfire configure` or set MCARE_FIREBASE_* defines at build time.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static FirebaseOptions get web => _options;
  static FirebaseOptions get android => _options;
  static FirebaseOptions get ios => _options;

  static FirebaseOptions get _options => FirebaseOptions(
    apiKey: AppEnv.firebaseApiKey,
    appId: AppEnv.firebaseAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
  );
}
