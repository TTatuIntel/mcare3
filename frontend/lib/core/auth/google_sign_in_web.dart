import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'google_redirect_auth_result.dart';

web.HTMLDivElement? _overlay;
web.HTMLStyleElement? _overlayStyle;

extension type _GoogleAccountsId(JSObject _) {
  external void initialize(JSObject config);
  external void renderButton(JSObject parent, JSObject options);
  external void cancel();
}

/// Normalise host — Google OAuth rejects `0.0.0.0`.
void warmUpGoogleSignIn() {
  _normalizeOriginIfNeeded();
}

void _normalizeOriginIfNeeded() {
  final host = web.window.location.hostname;
  if (host == '0.0.0.0') {
    final port = web.window.location.port;
    final path = '${web.window.location.pathname}${web.window.location.search}';
    final target = port.isEmpty
        ? 'http://localhost$path'
        : 'http://localhost:$port$path';
    web.window.location.href = target;
  }
}

bool _isGsiReady() => _accountsId() != null;

_GoogleAccountsId? _accountsId() {
  final google = globalContext.getProperty('google'.toJS);
  if (google == null || google.isUndefinedOrNull) return null;
  final accounts = (google as JSObject).getProperty('accounts'.toJS);
  if (accounts == null || accounts.isUndefinedOrNull) return null;
  final id = (accounts as JSObject).getProperty('id'.toJS);
  if (id == null || id.isUndefinedOrNull) return null;
  return id as _GoogleAccountsId;
}

/// Waits for the GSI script from `web/index.html`.
Future<void> ensureGoogleSignInLoaded() async {
  _normalizeOriginIfNeeded();
  for (var i = 0; i < 80; i++) {
    if (_isGsiReady()) return;
    await Future<void>.delayed(const Duration(milliseconds: 75));
  }
  throw StateError(
    'Google Sign-In could not load. Check your connection and try again.',
  );
}

/// After OAuth redirect, read auth payload from URL hash (once).
GoogleRedirectAuthResult? tryConsumeRedirectAuth() {
  final hash = web.window.location.hash;
  if (!hash.startsWith('#mcare_google=')) return null;

  try {
    final encoded = Uri.decodeComponent(hash.substring('#mcare_google='.length));
    final json = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (json is! Map) return null;
    final data = Map<String, dynamic>.from(json);

    _clearUrlHash();

    if (data['error'] != null) {
      return GoogleRedirectAuthResult(
        error: data['error'].toString(),
      );
    }

    final user = data['user'];
    return GoogleRedirectAuthResult(
      token: data['token'] as String?,
      user: user is Map ? Map<String, dynamic>.from(user) : null,
      hasHealthProfile: data['has_health_profile'] == true,
    );
  } catch (_) {
    _clearUrlHash();
    return const GoogleRedirectAuthResult(
      error: 'Could not complete Google sign-in.',
    );
  }
}

void _clearUrlHash() {
  final path = '${web.window.location.pathname}${web.window.location.search}';
  web.window.history.replaceState(null, '', path);
}

/// Google Identity Services — returns a verified ID token (no page redirect).
Future<String?> promptGoogleIdToken(
  String clientId, {
  bool selectAccount = true,
}) async {
  await ensureGoogleSignInLoaded();
  final gsi = _accountsId();
  if (gsi == null) {
    throw StateError('Google Sign-In is not available.');
  }

  final completer = Completer<String?>();
  var finished = false;

  void finish(String? token) {
    if (finished) return;
    finished = true;
    _tearDownOverlay();
    gsi.cancel();
    if (!completer.isCompleted) completer.complete(token);
  }

  final callback = ((JSAny raw) {
    final response = raw as JSObject;
    final credential = response.getProperty('credential'.toJS);
    if (credential != null && !credential.isUndefinedOrNull) {
      finish((credential as JSString).toDart);
    } else {
      finish(null);
    }
  }).toJS;

  final config = <String, Object?>{
    'client_id': clientId,
    'callback': callback,
    'auto_select': false,
    'cancel_on_tap_outside': true,
    'context': 'signin',
    'itp_support': true,
    if (selectAccount) 'prompt_parent_id': 'mcare-gsi-overlay',
  }.jsify()! as JSObject;

  gsi.initialize(config);

  final viewportW = web.window.innerWidth;
  final isNarrow = viewportW < 420;
  final btnWidth = (viewportW - (isNarrow ? 28 : 48) * 2).clamp(260, 360).toInt();

  final btnHost = web.HTMLDivElement()
    ..id = 'mcare-gsi-button-host'
    ..style.width = '100%'
    ..style.display = 'flex'
    ..style.justifyContent = 'center'
    ..style.minHeight = '44px';

  _showChooserOverlay(
    extraChild: btnHost,
    onCancel: () => finish(null),
  );

  final buttonOptions = <String, Object?>{
    'type': 'standard',
    'theme': 'outline',
    'size': 'large',
    'text': 'continue_with',
    'shape': 'pill',
    'width': btnWidth,
    'logo_alignment': 'left',
  }.jsify()! as JSObject;

  gsi.renderButton(btnHost, buttonOptions);

  return completer.future;
}

/// Full-page OAuth via Laravel (fallback when GSI is blocked).
Future<void> beginRedirectSignIn({
  required String apiBaseUrl,
  required bool createAccount,
}) async {
  _normalizeOriginIfNeeded();

  final completer = Completer<void>();
  var done = false;

  void finish() {
    if (done) return;
    done = true;
    _tearDownOverlay();
    if (!completer.isCompleted) completer.complete();
  }

  _showChooserOverlay(
    onContinue: () {
      final returnTo = _currentReturnUrl();
      final base = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final url = '$base/auth/google/redirect?'
          'return_to=${Uri.encodeComponent(returnTo)}'
          '&create_account=${createAccount ? 1 : 0}';
      web.window.location.href = url;
    },
    onCancel: finish,
  );

  return completer.future;
}

String _currentReturnUrl() {
  return '${web.window.location.origin}'
      '${web.window.location.pathname}'
      '${web.window.location.search}';
}

void _showChooserOverlay({
  void Function()? onContinue,
  void Function()? onCancel,
  web.HTMLElement? extraChild,
}) {
  _tearDownOverlay();

  final viewportW = web.window.innerWidth;
  final isNarrow = viewportW < 420;
  final outerPad = isNarrow ? 14 : 24;
  final innerPadH = isNarrow ? 16 : 20;
  final cardMaxW = (viewportW - outerPad * 2).clamp(280, 380);

  final overlay = web.HTMLDivElement()
    ..id = 'mcare-gsi-overlay'
    ..style.position = 'fixed'
    ..style.inset = '0'
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center'
    ..style.padding = '${outerPad}px'
    ..style.backgroundColor = 'rgba(15, 23, 42, 0.52)'
    ..style.zIndex = '2147483646'
    ..style.fontFamily = "'Inter', system-ui, sans-serif"
    ..style.boxSizing = 'border-box';

  overlay.addEventListener(
    'click',
    ((web.Event event) {
      if (identical(event.target, overlay)) onCancel?.call();
    }).toJS,
  );

  final card = web.HTMLDivElement()
    ..style.backgroundColor = '#ffffff'
    ..style.borderRadius = isNarrow ? '16px' : '20px'
    ..style.padding =
        isNarrow ? '20px ${innerPadH}px 18px' : '24px ${innerPadH}px 22px'
    ..style.maxWidth = '${cardMaxW}px'
    ..style.width = '100%'
    ..style.boxShadow = '0 24px 48px rgba(15, 23, 42, 0.18)'
    ..style.position = 'relative'
    ..style.boxSizing = 'border-box';

  final close = web.HTMLButtonElement()
    ..type = 'button'
    ..ariaLabel = 'Close'
    ..textContent = '×'
    ..style.cssText = '''
      position:absolute;top:8px;right:8px;border:none;background:transparent;
      color:#64748B;font-size:24px;line-height:1;cursor:pointer;padding:4px 6px;z-index:1;
    ''';
  close.addEventListener('click', ((web.Event _) => onCancel?.call()).toJS);

  final title = web.HTMLHeadingElement.h2()
    ..textContent = 'Sign in with Google'
    ..style.cssText = '''
      margin:0 28px 6px 0;font-size:${isNarrow ? '18px' : '20px'};
      font-weight:700;color:#0F172A;line-height:1.25;
    ''';

  final subtitle = web.HTMLParagraphElement()
    ..textContent = 'Choose your Google account to continue to mCare'
    ..style.cssText = '''
      margin:0 0 16px 0;font-size:${isNarrow ? '13px' : '14px'};
      line-height:1.45;color:#64748B;
    ''';

  card.append(close);
  card.append(title);
  card.append(subtitle);

  if (extraChild != null) {
    card.append(extraChild);
  } else if (onContinue != null) {
    final googleBtn = web.HTMLButtonElement()
      ..type = 'button'
      ..className = 'mcare-google-btn';
    final iconSpan = web.HTMLSpanElement()
      ..className = 'mcare-google-btn__icon'
      ..setAttribute('aria-hidden', 'true')
      ..textContent = 'G';
    final labelSpan = web.HTMLSpanElement()
      ..className = 'mcare-google-btn__label'
      ..textContent = 'Continue with Google';
    googleBtn.append(iconSpan);
    googleBtn.append(labelSpan);
    googleBtn.addEventListener('click', ((web.Event _) => onContinue()).toJS);
    card.append(googleBtn);
  }

  final hint = web.HTMLParagraphElement()
    ..textContent = 'Works with Gmail and Google Workspace.'
    ..style.cssText = '''
      margin:12px 0 0;font-size:11px;line-height:1.4;color:#94A3B8;text-align:center;
    ''';
  card.append(hint);
  overlay.append(card);
  web.document.body?.append(overlay);
  _overlay = overlay;

  _overlayStyle = web.HTMLStyleElement()
    ..id = 'mcare-gsi-overlay-style'
    ..textContent = '''
.mcare-google-btn {
  display:flex;align-items:center;justify-content:center;gap:10px;
  width:100%;max-width:100%;box-sizing:border-box;
  height:44px;padding:0 16px;margin:0;
  border:1px solid #DADCE0;border-radius:999px;
  background:#fff;color:#1F1F1F;font-size:14px;font-weight:600;
  font-family:inherit;cursor:pointer;transition:background .15s ease;
}
.mcare-google-btn:hover { background:#F8FAFC; }
.mcare-google-btn__icon {
  display:inline-flex;align-items:center;justify-content:center;
  width:20px;height:20px;border-radius:50%;
  background:linear-gradient(135deg,#4285F4 0%,#34A853 55%,#FBBC05 75%,#EA4335 100%);
  color:#fff;font-size:11px;font-weight:800;
}
.mcare-google-btn__label { white-space:nowrap;overflow:hidden;text-overflow:ellipsis; }
''';
  web.document.head?.append(_overlayStyle!);
}

Future<void> revokeGoogleSession() async {
  final gsi = _accountsId();
  gsi?.cancel();
}

void _tearDownOverlay() {
  _overlay?.remove();
  _overlay = null;
  _overlayStyle?.remove();
  _overlayStyle = null;
}
