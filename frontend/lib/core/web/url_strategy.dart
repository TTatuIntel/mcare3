/// Configures clean (path-based) URLs on Flutter web so email deep links like
/// `/reset-password?token=...` and `/accept-invite?token=...` resolve directly.
///
/// The real implementation lives in [url_strategy_web.dart] and is only pulled
/// in on web; every other platform gets the no-op [url_strategy_io.dart] stub,
/// which keeps `flutter_web_plugins` out of mobile/desktop builds.
export 'url_strategy_io.dart' if (dart.library.html) 'url_strategy_web.dart';
