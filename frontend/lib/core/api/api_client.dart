import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../async/app_busy.dart';
import '../env/app_env.dart';
import 'api_error_messages.dart';

/// HTTP wrapper for the Laravel API (`/api/v1`).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;

  void setToken(String? token) => _token = token;
  String? get token => _token;

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

  Future<Map<String, dynamic>> get(
    String path, {
    bool allowWhenBackendDisabled = false,
  }) async {
    if (!AppEnv.backendEnabled && !allowWhenBackendDisabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(http
        .get(Uri.parse(_url(path)), headers: _headers)
        .timeout(AppEnv.apiTimeout));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool allowWhenBackendDisabled = false,
  }) async {
    if (!AppEnv.backendEnabled && !allowWhenBackendDisabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(http
        .post(
          Uri.parse(_url(path)),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AppEnv.apiTimeout));
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
    AppBusy.instance.begin();
    try {
      final streamed = await req.send().timeout(AppEnv.apiTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } finally {
      AppBusy.instance.end();
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
    AppBusy.instance.begin();
    try {
      final streamed = await req.send().timeout(AppEnv.apiTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } finally {
      AppBusy.instance.end();
    }
  }

  /// Authenticated binary GET (document stream, exports, etc.).
  Future<Uint8List> getBytes(String path) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    AppBusy.instance.begin();
    try {
      final response = await http
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
    return _send(http
        .put(
          Uri.parse(_url(path)),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AppEnv.apiTimeout));
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(http
        .patch(
          Uri.parse(_url(path)),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AppEnv.apiTimeout));
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled — use mock repositories.');
    }
    return _send(http
        .delete(
          Uri.parse(_url(path)),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AppEnv.apiTimeout));
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> request) async {
    AppBusy.instance.begin();
    try {
      final response = await request;
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiErrorMessages.sanitize(e.toString()), 0);
    } finally {
      AppBusy.instance.end();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
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

    final message = ApiErrorMessages.sanitize(
      json?['message'] as String? ??
          'Request failed (${response.statusCode}).',
    );
    throw ApiException(message, response.statusCode);
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
