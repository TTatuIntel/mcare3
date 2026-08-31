import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'google_redirect_auth_result.dart';

web.HTMLDivElement? _overlay;
web.HTMLStyleElement? _overlayStyle;
web.HTMLElement? _previousFocus;
String? _previousBodyOverflow;

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
    final encoded = Uri.decodeComponent(
      hash.substring('#mcare_google='.length),
    );
    final json = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (json is! Map) return null;
    final data = Map<String, dynamic>.from(json);

    _clearUrlHash();

    if (data['error'] != null) {
      return GoogleRedirectAuthResult(error: data['error'].toString());
    }

    final user = data['user'];
    return GoogleRedirectAuthResult(
      token: data['token'] as String?,
      user: user is Map ? Map<String, dynamic>.from(user) : null,
      hasHealthProfile: data['has_health_profile'] == true,
      remember: data['remember'] == true,
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
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
  bool createAccount = false,
  String serverClientId = '',
  String iosClientId = '',
}) async {
  await ensureGoogleSignInLoaded();
  final gsi = _accountsId();
  if (gsi == null) {
    throw StateError('Google Sign-In is not available.');
  }

  final completer = Completer<String?>();
  var finished = false;
  Timer? chooserTimeout;

  void finish(String? token) {
    if (finished) return;
    finished = true;
    chooserTimeout?.cancel();
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

  final config =
      <String, Object?>{
            'client_id': clientId,
            'callback': callback,
            'auto_select': false,
            'cancel_on_tap_outside': true,
            'context': 'signin',
            'itp_support': true,
            if (selectAccount) 'prompt_parent_id': 'mcare-gsi-overlay',
          }.jsify()!
          as JSObject;

  gsi.initialize(config);

  final viewportW = web.window.innerWidth;
  final isNarrow = viewportW < 420;
  final btnWidth = (viewportW - (isNarrow ? 28 : 48) * 2)
      .clamp(260, 360)
      .toInt();

  final btnHost = web.HTMLDivElement()
    ..id = 'mcare-gsi-button-host'
    ..style.width = '100%'
    ..style.display = 'flex'
    ..style.justifyContent = 'center'
    ..style.minHeight = '44px';

  _showChooserOverlay(
    createAccount: createAccount,
    extraChild: btnHost,
    onCancel: () => finish(null),
  );
  chooserTimeout = Timer(const Duration(minutes: 2), () => finish(null));

  final buttonOptions =
      <String, Object?>{
            'type': 'standard',
            'theme': 'outline',
            'size': 'large',
            'text': 'continue_with',
            'shape': 'pill',
            'width': btnWidth,
            'logo_alignment': 'left',
          }.jsify()!
          as JSObject;

  gsi.renderButton(btnHost, buttonOptions);

  return completer.future;
}

/// Full-page OAuth via Laravel (fallback when GSI is blocked).
Future<void> beginRedirectSignIn({
  required String apiBaseUrl,
  required bool createAccount,
  required bool remember,
  required String deviceName,
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
    createAccount: createAccount,
    onContinue: () {
      final returnTo = _currentReturnUrl();
      final base = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final url =
          '$base/auth/google/redirect?'
          'return_to=${Uri.encodeComponent(returnTo)}'
          '&create_account=${createAccount ? 1 : 0}'
          '&remember=${remember ? 1 : 0}'
          '&device_name=${Uri.encodeQueryComponent(deviceName)}';
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
  bool createAccount = false,
  void Function()? onContinue,
  void Function()? onCancel,
  web.HTMLElement? extraChild,
}) {
  _tearDownOverlay();

  final viewportW = web.window.innerWidth;
  final isNarrow = viewportW < 420;
  final outerPad = isNarrow ? 12 : 24;
  final cardMaxW = (viewportW - outerPad * 2).clamp(296, 420);

  final activeElement = web.document.activeElement;
  _previousFocus = activeElement?.isA<web.HTMLElement>() == true
      ? activeElement as web.HTMLElement
      : null;
  final body = web.document.body;
  _previousBodyOverflow = body?.style.overflow;
  if (body != null) body.style.overflow = 'hidden';

  final overlay = web.HTMLDivElement()
    ..id = 'mcare-gsi-overlay'
    ..setAttribute('role', 'presentation')
    ..style.position = 'fixed'
    ..style.inset = '0'
    ..style.display = 'flex'
    ..style.alignItems = isNarrow ? 'flex-end' : 'center'
    ..style.justifyContent = 'center'
    ..style.padding = '${outerPad}px'
    ..style.backgroundColor = 'rgba(15, 23, 42, 0.64)'
    ..style.backdropFilter = 'blur(5px)'
    ..style.zIndex = '2147483646'
    ..style.fontFamily =
        "Inter, ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif"
    ..style.boxSizing = 'border-box';

  overlay.addEventListener(
    'click',
    ((web.Event event) {
      if (identical(event.target, overlay)) onCancel?.call();
    }).toJS,
  );

  final card = web.HTMLDivElement()
    ..className = 'mcare-gsi-card'
    ..setAttribute('role', 'dialog')
    ..setAttribute('aria-modal', 'true')
    ..setAttribute('aria-labelledby', 'mcare-gsi-title')
    ..setAttribute('aria-describedby', 'mcare-gsi-description')
    ..tabIndex = -1
    ..style.backgroundColor = '#ffffff'
    ..style.borderRadius = isNarrow ? '24px' : '28px'
    ..style.padding = isNarrow ? '20px 18px 18px' : '24px 24px 22px'
    ..style.maxWidth = '${cardMaxW}px'
    ..style.width = '100%'
    ..style.boxShadow =
        '0 32px 80px rgba(15, 23, 42, 0.28), 0 8px 24px rgba(15, 23, 42, 0.14)'
    ..style.position = 'relative'
    ..style.boxSizing = 'border-box';

  overlay.addEventListener(
    'keydown',
    ((web.Event event) {
      final keyboardEvent = event as web.KeyboardEvent;
      if (keyboardEvent.key == 'Escape') {
        keyboardEvent.preventDefault();
        onCancel?.call();
      }
    }).toJS,
  );

  final close = web.HTMLButtonElement()
    ..type = 'button'
    ..className = 'mcare-gsi-close'
    ..ariaLabel = 'Close'
    ..textContent = '×'
    ..style.cssText = '';
  close.addEventListener('click', ((web.Event _) => onCancel?.call()).toJS);

  final providerRow = web.HTMLDivElement()..className = 'mcare-gsi-provider';
  final providerLogo = web.HTMLSpanElement()
    ..className = 'mcare-gsi-logo'
    ..setAttribute('aria-hidden', 'true');
  final providerCopy = web.HTMLDivElement()
    ..className = 'mcare-gsi-provider-copy';
  final providerName = web.HTMLSpanElement()
    ..className = 'mcare-gsi-provider-name'
    ..textContent = 'Google Sign-In';
  final providerLabel = web.HTMLSpanElement()
    ..className = 'mcare-gsi-provider-label'
    ..textContent = createAccount
        ? 'Verified account registration'
        : 'Secure account access';
  providerCopy.append(providerName);
  providerCopy.append(providerLabel);
  providerRow.append(providerLogo);
  providerRow.append(providerCopy);

  final title = web.HTMLHeadingElement.h2()
    ..id = 'mcare-gsi-title'
    ..textContent = createAccount
        ? 'Create your mCare account'
        : 'Continue to mCare'
    ..style.cssText = '';

  final subtitle = web.HTMLParagraphElement()
    ..id = 'mcare-gsi-description'
    ..textContent = createAccount
        ? 'Use an existing Google account. Google verifies your email and mCare creates your patient account immediately.'
        : 'Choose a Google account. Your password stays with Google—we only receive your verified name and email.'
    ..style.cssText = '';

  card.append(close);
  card.append(providerRow);
  card.append(title);
  card.append(subtitle);

  final actionHost = web.HTMLDivElement()..className = 'mcare-gsi-action-host';
  if (extraChild != null) {
    actionHost.append(extraChild);
  } else if (onContinue != null) {
    final googleBtn = web.HTMLButtonElement()
      ..type = 'button'
      ..className = 'mcare-google-btn';
    final iconSpan = web.HTMLSpanElement()
      ..className = 'mcare-google-btn__icon'
      ..setAttribute('aria-hidden', 'true');
    final labelSpan = web.HTMLSpanElement()
      ..className = 'mcare-google-btn__label'
      ..textContent = createAccount
          ? 'Create account with Google'
          : 'Continue with Google';
    googleBtn.append(iconSpan);
    googleBtn.append(labelSpan);
    googleBtn.addEventListener(
      'click',
      ((web.Event _) {
        if (googleBtn.disabled) return;
        googleBtn.disabled = true;
        googleBtn.setAttribute('aria-busy', 'true');
        labelSpan.textContent = 'Opening Google…';
        onContinue();
      }).toJS,
    );
    actionHost.append(googleBtn);
  }
  card.append(actionHost);

  final trust = web.HTMLDivElement()..className = 'mcare-gsi-trust';
  final trustIcon = web.HTMLSpanElement()
    ..className = 'mcare-gsi-trust-icon'
    ..setAttribute('aria-hidden', 'true')
    ..textContent = '✓';
  final trustText = web.HTMLSpanElement()
    ..textContent = 'Protected sign-in · Gmail and Google Workspace supported';
  trust.append(trustIcon);
  trust.append(trustText);
  card.append(trust);
  overlay.append(card);
  web.document.body?.append(overlay);
  _overlay = overlay;

  _overlayStyle = web.HTMLStyleElement()
    ..id = 'mcare-gsi-overlay-style'
    ..textContent =
        '''
#mcare-gsi-overlay { animation:mcare-gsi-fade .18s ease-out both; }
.mcare-gsi-card {
  border:1px solid rgba(226,232,240,.94);
  animation:mcare-gsi-rise .24s cubic-bezier(.22,.8,.3,1) both;
}
.mcare-gsi-close {
  position:absolute;top:14px;right:14px;display:grid;place-items:center;
  width:38px;height:38px;padding:0;border:1px solid #E2E8F0;border-radius:12px;
  background:#F8FAFC;color:#475569;font:400 25px/1 system-ui;cursor:pointer;
  transition:background .15s ease,border-color .15s ease,transform .15s ease;
}
.mcare-gsi-close:hover { background:#F1F5F9;border-color:#CBD5E1; }
.mcare-gsi-close:active { transform:scale(.96); }
.mcare-gsi-provider { display:flex;align-items:center;gap:11px;margin:0 48px 20px 0; }
.mcare-gsi-logo {
  display:grid;place-items:center;flex:0 0 auto;width:40px;height:40px;
  border:1px solid #E2E8F0;border-radius:13px;background:#fff;
  box-shadow:0 5px 14px rgba(15,23,42,.08);
  background:#fff url('https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png') center/24px 24px no-repeat;
}
.mcare-gsi-provider-copy { display:flex;min-width:0;flex-direction:column;gap:1px; }
.mcare-gsi-provider-name { color:#0F172A;font-size:13px;font-weight:750;line-height:1.3; }
.mcare-gsi-provider-label { color:#64748B;font-size:11px;font-weight:500;line-height:1.3; }
#mcare-gsi-title {
  margin:0 42px 7px 0;color:#0F172A;font-size:${isNarrow ? '21px' : '23px'};
  font-weight:780;letter-spacing:-.025em;line-height:1.2;
}
#mcare-gsi-description {
  margin:0;color:#64748B;font-size:${isNarrow ? '13px' : '13.5px'};
  line-height:1.55;
}
.mcare-gsi-action-host { display:flex;justify-content:center;width:100%;margin-top:20px; }
#mcare-gsi-button-host { overflow:hidden;border-radius:12px; }
.mcare-google-btn {
  display:flex;align-items:center;justify-content:center;gap:10px;
  width:100%;max-width:100%;box-sizing:border-box;
  height:48px;padding:0 16px;margin:0;border:1px solid #CBD5E1;border-radius:12px;
  background:#fff;color:#1F1F1F;font-size:14px;font-weight:650;font-family:inherit;
  cursor:pointer;box-shadow:0 2px 5px rgba(15,23,42,.06);
  transition:background .15s ease,border-color .15s ease,box-shadow .15s ease;
}
.mcare-google-btn:hover { background:#F8FAFC;border-color:#94A3B8;box-shadow:0 4px 10px rgba(15,23,42,.09); }
.mcare-google-btn:disabled { cursor:wait;opacity:.72; }
.mcare-google-btn__icon {
  display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;
  background:url('https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png') center/20px 20px no-repeat;
}
.mcare-google-btn__label { white-space:nowrap;overflow:hidden;text-overflow:ellipsis; }
.mcare-gsi-trust {
  display:flex;align-items:flex-start;justify-content:center;gap:7px;margin-top:16px;
  color:#64748B;font-size:10.5px;font-weight:550;line-height:1.45;text-align:center;
}
.mcare-gsi-trust-icon {
  display:grid;place-items:center;flex:0 0 auto;width:16px;height:16px;margin-top:-1px;
  border-radius:50%;background:#ECFDF5;color:#047857;font-size:10px;font-weight:800;
}
.mcare-gsi-close:focus-visible,.mcare-google-btn:focus-visible,.mcare-gsi-card:focus-visible {
  outline:3px solid rgba(79,70,229,.28);outline-offset:2px;
}
@keyframes mcare-gsi-fade { from { opacity:0; } to { opacity:1; } }
@keyframes mcare-gsi-rise { from { opacity:0;transform:translateY(14px) scale(.985); } to { opacity:1;transform:none; } }
@media (prefers-reduced-motion:reduce) {
  #mcare-gsi-overlay,.mcare-gsi-card { animation:none; }
  .mcare-gsi-close,.mcare-google-btn { transition:none; }
}
@media (max-width:419px) {
  .mcare-gsi-card { border-radius:24px 24px 18px 18px !important; }
}
''';
  web.document.head?.append(_overlayStyle!);

  card.focus();
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
  final body = web.document.body;
  if (body != null && _previousBodyOverflow != null) {
    body.style.overflow = _previousBodyOverflow!;
  }
  _previousBodyOverflow = null;
  _previousFocus?.focus();
  _previousFocus = null;
}
