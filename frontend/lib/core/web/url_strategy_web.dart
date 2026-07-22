import 'package:flutter_web_plugins/url_strategy.dart';

/// Switches the browser from the default hash strategy (`/#/...`) to clean
/// path URLs (`/reset-password?token=...`). Requires the host to serve
/// `index.html` for unknown paths (see `web/.htaccess` for Apache/XAMPP).
void configureWebUrlStrategy() => usePathUrlStrategy();
