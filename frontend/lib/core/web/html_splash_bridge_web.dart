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

bool isNewBrowserSession() => _mcareNewSession.toDart;
