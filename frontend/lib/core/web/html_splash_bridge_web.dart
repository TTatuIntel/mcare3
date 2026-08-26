import 'dart:js_interop';

@JS('CustomEvent')
extension type _JsCustomEvent._(JSObject _) implements JSObject {
  external factory _JsCustomEvent(String type);
}

@JS('window.dispatchEvent')
external void _jsDispatchEvent(JSObject event);

@JS('window.__mcareNewSession')
external JSBoolean get _mcareNewSession;

void dismissHtmlSplash() {
  _jsDispatchEvent(_JsCustomEvent('mcare-ready'));
}

/// Brings the HTML splash back. The page is not reloaded on a hot restart,
/// so this is what covers the gap while Flutter rebuilds its canvas.
void showHtmlSplash() {
  _jsDispatchEvent(_JsCustomEvent('mcare-loading'));
}

bool isNewBrowserSession() => _mcareNewSession.toDart;
