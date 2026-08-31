import 'external_link_stub.dart'
    if (dart.library.io) 'external_link_native.dart'
    if (dart.library.js_interop) 'external_link_web.dart'
    as platform;

/// Key-free Google Maps URLs and cross-platform external-app launching.
///
/// Embedded maps need restricted SDK keys, but search and directions URLs do
/// not. Keeping this fallback available means emergency location actions work
/// even when the embedded Maps SDK is disabled or temporarily unavailable.
class GoogleMapsService {
  GoogleMapsService._();

  static Uri searchUri(double latitude, double longitude) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': '$latitude,$longitude'},
  );

  static Uri directionsUri(double latitude, double longitude) => Uri.https(
    'www.google.com',
    '/maps/dir/',
    {'api': '1', 'destination': '$latitude,$longitude'},
  );

  static Future<bool> openCoordinates(
    double latitude,
    double longitude, {
    bool directions = false,
  }) => openUri(
    directions
        ? directionsUri(latitude, longitude)
        : searchUri(latitude, longitude),
  );

  static Future<bool> openUrl(String value) async {
    final uri = Uri.tryParse(value);
    return uri != null && await openUri(uri);
  }

  /// Opens [uri] outside the app: the Maps app on mobile, a new tab on web.
  ///
  /// Web goes through an anchor with `rel="noopener"` rather than
  /// `window.open`. Google redirects `/maps/search/?api=1` to the canonical
  /// `/maps?q=` URL, and that document carries
  /// `Cross-Origin-Opener-Policy: same-origin` — with an opener still attached
  /// Firefox refuses the load (NS_ERROR_DOM_COOP_FAILED).
  static Future<bool> openUri(Uri uri) => platform.openExternal(uri);
}
