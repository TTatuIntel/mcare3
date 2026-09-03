import 'package:flutter/foundation.dart';

import 'html_splash_bridge_stub.dart'
    if (dart.library.html) 'html_splash_bridge_web.dart'
    as impl;

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

  /// Re-reveal the splash while the app boots.
  ///
  /// A hot restart re-runs `main()` without reloading the page, so the Dart
  /// side starts fresh while the DOM keeps whatever state the previous run
  /// left behind. Without this the splash stayed dismissed and the restart
  /// showed a blank page until Flutter finished rebuilding its canvas.
  static void show() {
    if (!kIsWeb) return;
    _dismissed = false;
    impl.showHtmlSplash();
  }

  /// True when the page was opened fresh (hard refresh, new tab, browser
  /// close+reopen) — i.e. the JS sessionStorage flag was absent.
  /// Always false on non-web platforms.
  static bool isNewBrowserSession() {
    if (!kIsWeb) return false;
    return impl.isNewBrowserSession();
  }
}
