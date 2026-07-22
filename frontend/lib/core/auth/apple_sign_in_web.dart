import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'apple_sign_in_result.dart';

extension type _AppleIDAuth(JSObject _) {
  external void init(JSObject config);
  external JSPromise<JSObject> signIn();
}

_AppleIDAuth? _appleAuth() {
  final appleId = globalContext.getProperty('AppleID'.toJS);
  if (appleId == null || appleId.isUndefinedOrNull) return null;
  final auth = (appleId as JSObject).getProperty('auth'.toJS);
  if (auth == null || auth.isUndefinedOrNull) return null;
  return auth as _AppleIDAuth;
}

/// Waits for the Apple JS SDK (loaded from `web/index.html`) to be ready.
Future<void> _ensureLoaded() async {
  for (var i = 0; i < 80; i++) {
    if (_appleAuth() != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 75));
  }
  throw StateError(
    'Apple Sign-In could not load. Check your connection and that the '
    'AppleID SDK <script> is present in web/index.html.',
  );
}

String? _str(JSObject? obj, String key) {
  if (obj == null) return null;
  final value = obj.getProperty(key.toJS);
  if (value == null || value.isUndefinedOrNull) return null;
  return (value as JSString).toDart;
}

Future<AppleSignInResult?> requestAppleCredentials({
  required String clientId,
  required String redirectUri,
}) async {
  await _ensureLoaded();
  final auth = _appleAuth()!;

  final config = JSObject()
    ..setProperty('clientId'.toJS, clientId.toJS)
    ..setProperty('scope'.toJS, 'name email'.toJS)
    ..setProperty('redirectURI'.toJS, redirectUri.toJS)
    ..setProperty('usePopup'.toJS, true.toJS);
  auth.init(config);

  final JSObject response;
  try {
    response = await auth.signIn().toDart;
  } catch (_) {
    // Popup dismissed / cancelled by the user.
    return null;
  }

  final authorization = response.getProperty('authorization'.toJS) as JSObject?;
  final idToken = _str(authorization, 'id_token');
  if (idToken == null || idToken.isEmpty) return null;

  // `user` (with name/email) is only present on the very first authorization.
  final user = response.getProperty('user'.toJS) as JSObject?;
  final name = user?.getProperty('name'.toJS) as JSObject?;

  return AppleSignInResult(
    idToken: idToken,
    email: _str(user, 'email'),
    firstName: _str(name, 'firstName'),
    lastName: _str(name, 'lastName'),
  );
}
