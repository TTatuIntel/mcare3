import 'package:url_launcher/url_launcher.dart';

/// Hands [uri] to the platform handler — Google Maps, the dialer, or the
/// default browser, depending on the scheme.
Future<bool> openExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
