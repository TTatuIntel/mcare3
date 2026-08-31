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

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: AppEnv.firebaseWebApiKey,
    appId: AppEnv.firebaseWebAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
    authDomain: _emptyToNull(AppEnv.firebaseAuthDomain),
    storageBucket: _emptyToNull(AppEnv.firebaseStorageBucket),
    measurementId: _emptyToNull(AppEnv.firebaseMeasurementId),
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: AppEnv.firebaseAndroidApiKey,
    appId: AppEnv.firebaseAndroidAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
    storageBucket: _emptyToNull(AppEnv.firebaseStorageBucket),
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: AppEnv.firebaseIosApiKey,
    appId: AppEnv.firebaseIosAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
    storageBucket: _emptyToNull(AppEnv.firebaseStorageBucket),
    iosBundleId: AppEnv.firebaseIosBundleId,
  );

  static String? _emptyToNull(String value) => value.isEmpty ? null : value;
}
