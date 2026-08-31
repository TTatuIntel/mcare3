/// Fallback for targets that expose neither `dart:io` nor `dart:html`.
///
/// Never selected in practice — every Flutter target resolves to the native or
/// the web variant. Returning false keeps callers on their "couldn't open"
/// path instead of reporting a launch that never happened.
Future<bool> openExternal(Uri uri) async => false;
