import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../async/app_busy.dart';
import '../async/request_cache.dart';
import '../env/app_env.dart';
import 'api_error_messages.dart';

/// HTTP wrapper for the Laravel API (`/api/v1`).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// The transport every verb below goes through.
  ///
  /// This used to be `package:http`'s top-level functions, which open and
  /// close a client per call and leave no seam for tests: under
  /// `flutter_test` every request returns 400, so any test touching an
  /// API-backed mutation saw it fail and roll back. One pooled client keeps
  /// connections alive in production and lets tests swap in a stub.
  http.Client _transport = http.Client();

  /// Replaces the HTTP transport. Pass null to restore the real one.
  ///
  /// Test-only seam — production code must never call this.
  void setTransportForTesting(http.Client? client) {
    _transport = client ?? http.Client();
  }

  String? _token;

  void setToken(String? token) {
    // Identity change: drop every cached response so one account's data can
    // never be served to another.
    if (_token != token) RequestCache.instance.clear();
    _token = token;
  }

  String? get token => _token;

  /// Called once when the API rejects the caller's bearer token (a 401 while a
  /// token is set), so a revoked or expired session is ended in one place
  /// instead of surfacing as a different error on every screen. Wired in
  /// `main()` to `SessionRecovery.forceSignOut`.
  void Function()? onSessionRejected;

  /// Endpoints where a 401 is the answer to the question, not a dead session:
  /// these present credentials rather than a live token. Signing in with the
  /// wrong password must not be read as "your session expired".
  ///
  /// [_noteRejection] also requires a signed-in user, which covers session
  /// restore (`/auth/me` before anyone is signed in) and the logout call that
  /// [AuthState.signOut] fires with the token being discarded.
  static const _credentialPaths = <String>{
    '/auth/login',
    '/auth/register',
    '/auth/google',
    '/auth/apple',
    '/auth/logout',
    '/auth/forgot-password',
    '/auth/reset-password',
    '/auth/verify-reset-otp',
    '/auth/verify-otp',
    '/auth/resend-otp',
    '/auth/accept-invite',
  };

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String _url(String path) {
    final base = AppEnv.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  /// GET a JSON endpoint.
  ///
  /// Pass [cacheFor] to serve repeat reads of the same path from memory for
  /// that long, and to collapse identical concurrent reads into one request.
  /// Left null (the default) every call hits the network exactly as before —
  /// caching never changes behaviour unless a caller opts in.
  Future<Map<String, dynamic>> get(
    String path, {
    bool allowWhenBackendDisabled = false,
    Duration? cacheFor,
    bool forceRefresh = false,
  }) async {
    if (!AppEnv.backendEnabled && !allowWhenBackendDisabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }

    Future<Map<String, dynamic>> request() => _send(
      _transport
          .get(Uri.parse(_url(path)), headers: _headers)
          .timeout(AppEnv.apiTimeout),
      path: path,
    );

    if (cacheFor == null) return request();

    // Keyed by token as well as path: a cached response must never leak
    // across accounts if a different user signs in.
    final key = 'GET $path#${_token?.hashCode ?? 0}';
    return RequestCache.instance.read(
      key,
      request,
      ttl: cacheFor,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool allowWhenBackendDisabled = false,
  }) async {
    if (!AppEnv.backendEnabled && !allowWhenBackendDisabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(
      _transport
          .post(
            Uri.parse(_url(path)),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(AppEnv.apiTimeout),
      path: path,
      mutation: true,
    );
  }

  /// Multipart POST for file uploads. Omits JSON Content-Type.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    bool allowWhenBackendDisabled = false,
  }) async {
    if (!AppEnv.backendEnabled && !allowWhenBackendDisabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    final req = http.MultipartRequest('POST', Uri.parse(_url(path)));
    req.headers['Accept'] = 'application/json';
    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    req.fields.addAll(fields);
    req.files.addAll(files);
    AppBusy.instance.begin(mutation: true);
    try {
      final streamed = await _transport.send(req).timeout(AppEnv.apiTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response, path);
    } finally {
      AppBusy.instance.end(mutation: true);
    }
  }

  /// Multipart PATCH for document updates with optional file replacement.
  Future<Map<String, dynamic>> patchMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    final req = http.MultipartRequest('PATCH', Uri.parse(_url(path)));
    req.headers['Accept'] = 'application/json';
    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    req.fields.addAll(fields);
    req.files.addAll(files);
    AppBusy.instance.begin(mutation: true);
    try {
      final streamed = await _transport.send(req).timeout(AppEnv.apiTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response, path);
    } finally {
      AppBusy.instance.end(mutation: true);
    }
  }

  /// Authenticated binary GET (document stream, exports, etc.).
  Future<Uint8List> getBytes(String path) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    AppBusy.instance.begin();
    try {
      final response = await _transport
          .get(
            Uri.parse(_url(path)),
            headers: {
              'Accept': '*/*',
              if (_token != null) 'Authorization': 'Bearer $_token',
            },
          )
          .timeout(AppEnv.apiTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      _noteRejection(response.statusCode, path);
      final message = ApiErrorMessages.sanitize(
        json?['message'] as String? ??
            'Request failed (${response.statusCode}).',
      );
      throw ApiException(message, response.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiErrorMessages.sanitize(e.toString()), 0);
    } finally {
      AppBusy.instance.end();
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(
      _transport
          .put(
            Uri.parse(_url(path)),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(AppEnv.apiTimeout),
      path: path,
      mutation: true,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(
      _transport
          .patch(
            Uri.parse(_url(path)),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(AppEnv.apiTimeout),
      path: path,
      mutation: true,
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(
      _transport
          .delete(
            Uri.parse(_url(path)),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(AppEnv.apiTimeout),
      path: path,
      mutation: true,
    );
  }

  /// [mutation] marks a write the user is waiting on, which is what raises the
  /// on-screen indicator. Reads only feed the slim top bar.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> request, {
    required String path,
    bool mutation = false,
  }) async {
    AppBusy.instance.begin(mutation: mutation);
    try {
      final response = await request;
      return _decode(response, path);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiErrorMessages.sanitize(e.toString()), 0);
    } finally {
      AppBusy.instance.end(mutation: mutation);
    }
  }

  Map<String, dynamic> _decode(http.Response response, String path) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json == null) {
        throw ApiException('Invalid JSON response.', response.statusCode);
      }
      if (json['success'] == false) {
        throw ApiException(
          ApiErrorMessages.sanitize(
            json['message'] as String? ?? 'Request failed.',
          ),
          response.statusCode,
        );
      }
      return json;
    }

    _noteRejection(response.statusCode, path);
    final message = ApiErrorMessages.sanitize(
      json?['message'] as String? ?? 'Request failed (${response.statusCode}).',
    );
    throw ApiException(message, response.statusCode);
  }

  /// Reports a rejected bearer token to [onSessionRejected].
  ///
  /// 401 only. A 403 means the account is real but not allowed to do this one
  /// thing — an assistant reaching an admin-only endpoint — and signing that
  /// user out would be wrong. The caller still gets its [ApiException]; this
  /// only adds the session-level consequence.
  void _noteRejection(int statusCode, String path) {
    if (statusCode != 401) return;
    if (_token == null) return;
    if (_credentialPaths.contains(path)) return;
    onSessionRejected?.call();
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
