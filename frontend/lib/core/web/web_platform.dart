/// Platform facade for browser-only APIs (window.open, localStorage,
/// Web Audio). The real implementation lives in [web_platform_web.dart] and is
/// only compiled on web; everywhere else (native, `flutter test` VM) the
/// no-op stub is used so `package:web` never reaches non-web builds.
export 'web_platform_stub.dart' if (dart.library.html) 'web_platform_web.dart';
