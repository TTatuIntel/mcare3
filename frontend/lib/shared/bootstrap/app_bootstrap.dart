import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/web/html_splash_bridge.dart';
import '../constants/route_names.dart';
import '../services/auth_service.dart';
import '../services/auth_storage.dart';
import '../state/settings_state.dart';

/// Startup work run behind the splash screen — fonts, warm caches, future
/// session restore. Keeps first paint fast by deferring heavy work here.
class AppBootstrap {
  AppBootstrap._();

  /// Set to true in widget tests to skip optional startup delays.
  static bool fastMode = false;

  static const Duration _maxWait = Duration(seconds: 3);

  static Future<BootstrapResult> run() async {
    try {
      if (!fastMode) {
        // Font preloading is a network request — run it alongside settings but
        // do not let it gate the splash: fire-and-forget if it takes too long.
        _preloadFonts().timeout(const Duration(seconds: 2)).catchError((_) {});
      }
      await Future.wait([
        _warmCaches(),
        SettingsState.instance.loadPersisted(),
      ]).timeout(_maxWait);
    } catch (_) {
      // Never block launch on startup failures.
    }

    // Hard refresh / new browser session (tab close+reopen, Ctrl+F5) ends any
    // session the user did NOT ask to keep. A "keep me signed in" token is
    // deliberately preserved here — it is stored outside the tab session and
    // is what restores the user below.
    if (HtmlSplashBridge.isNewBrowserSession()) {
      await AuthStorage.clearUnremembered();
    }

    final googleResult = kIsWeb
        ? await AuthService.instance.tryCompleteGoogleRedirect()
        : null;
    if (googleResult != null &&
        googleResult.isSuccess &&
        googleResult.user != null) {
      return BootstrapResult(
        initialRoute: AuthService.instance.routeForAuthUser(
          googleResult.user!,
          googleResult.seededProfile,
        ),
        googleAuthResult: googleResult,
      );
    }

    final restoredRoute = await AuthService.instance.tryRestoreSession();

    return BootstrapResult(
      initialRoute: restoredRoute ?? RouteNames.home,
      googleAuthResult: googleResult,
    );
  }

  static Future<void> _preloadFonts() async {
    await GoogleFonts.pendingFonts([GoogleFonts.outfit()]);
  }

  static Future<void> _warmCaches() async {
    // Reserved for persisted session restore, feature flags, etc.
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class BootstrapResult {
  const BootstrapResult({required this.initialRoute, this.googleAuthResult});

  final String initialRoute;

  /// Set when returning from Google OAuth redirect (success or failure).
  final AuthFlowResult? googleAuthResult;
}
