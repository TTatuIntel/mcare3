import 'package:flutter/foundation.dart';

import 'html_splash_bridge_stub.dart'
    if (dart.library.html) 'html_splash_bridge_web.dart' as impl;

/// Hands off from the HTML pre-Flutter splash to the Flutter splash UI,
/// and exposes session-guard helpers to AppBootstrap.
class HtmlSplashBridge {
  HtmlSplashBridge._();

  static var _dismissed = false;

  /// Call once Flutter has painted its first real screen.
  static void dismiss() {
    if (_dismissed || !kIsWeb) return;
    _dismissed = true;
    impl.dismissHtmlSplash();
  }

  /// True when the page was opened fresh (hard refresh, new tab, browser
  /// close+reopen) — i.e. the JS sessionStorage flag was absent.
  /// Always false on non-web platforms.
  static bool isNewBrowserSession() {
    if (!kIsWeb) return false;
    return impl.isNewBrowserSession();
  }
}
