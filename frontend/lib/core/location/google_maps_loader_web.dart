import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<bool>? _load;

bool _isLoaded() {
  final google = web.window.getProperty<JSAny?>('google'.toJS);
  if (google == null || google.isUndefinedOrNull) return false;
  final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
  return maps != null && !maps.isUndefinedOrNull;
}

Future<bool> ensureGoogleMapsLoaded(String webApiKey) {
  if (_isLoaded()) return Future.value(true);
  return _load ??= _loadScript(webApiKey);
}

Future<bool> _loadScript(String webApiKey) async {
  if (webApiKey.trim().isEmpty) return false;

  final completer = Completer<bool>();
  final script = web.HTMLScriptElement()
    ..id = 'mcare-google-maps-sdk'
    ..async = true
    ..defer = true
    ..src = Uri.https('maps.googleapis.com', '/maps/api/js', {
      'key': webApiKey,
      'v': 'weekly',
    }).toString();

  script.addEventListener(
    'load',
    ((web.Event _) => completer.complete(_isLoaded())).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) => completer.complete(false)).toJS,
  );
  web.document.head?.append(script);

  return completer.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () => false,
  );
}
