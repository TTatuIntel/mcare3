import 'package:web/web.dart' as web;

/// Opens [uri] in a new tab with the opener relationship severed.
///
/// `window.open` — what `url_launcher`'s `webOnlyWindowName` uses — leaves the
/// new tab holding a reference back to this one. Google Maps serves
/// `Cross-Origin-Opener-Policy: same-origin`, so when the tab follows Google's
/// redirect from `/maps/search/?api=1` to the canonical `/maps?q=` URL, the
/// browsing-context group cannot be switched and Firefox blocks the load with
/// NS_ERROR_DOM_COOP_FAILED. An anchor carrying `rel="noopener"` starts the tab
/// in its own group, so there is no opener for COOP to sever. `noreferrer`
/// additionally keeps patient-facing URLs out of Google's referrer logs.
Future<bool> openExternal(Uri uri) async {
  final anchor = web.HTMLAnchorElement()
    ..href = uri.toString()
    ..target = '_blank'
    ..rel = 'noopener noreferrer';
  anchor.style.display = 'none';

  final body = web.document.body;
  if (body == null) return false;

  body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
