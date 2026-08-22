import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../shared/auth/auth_state.dart';
import '../api/api_client.dart';
import '../env/app_env.dart';
import 'session_poller.dart';

/// README §7.1 primary real-time channel.
///
/// Speaks the Pusher wire protocol (compatible with Laravel Reverb) as a
/// pure-Dart WebSocket client — no native deps, works on web + mobile +
/// desktop from one implementation.
///
/// Behaviour is opt-in: unless [AppEnv.realtimeEnabled] is true (both
/// [AppEnv.wsUrl] and [AppEnv.wsAppKey] set), [attach] is a no-op and the
/// app runs REST/polling only. This keeps local dev unaffected until the
/// Reverb server is actually up.
///
/// Event handling is intentionally minimal: when a `vital.alert` frame
/// arrives, we trigger [SessionPoller.triggerNow] which refreshes the
/// same state stores the REST path populates. That keeps the state
/// layer completely unaware of the WS channel — one code path, two
/// delivery mechanisms.
class RealtimeChannel {
  RealtimeChannel._();
  static final RealtimeChannel instance = RealtimeChannel._();

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  String? _socketId;
  bool _attached = false;
  int _backoffSeconds = 2;

  /// Connect if realtime is enabled and a user is signed in. Idempotent —
  /// calling repeatedly with the same session is a no-op.
  Future<void> attach() async {
    if (!AppEnv.realtimeEnabled) return;
    if (_attached) return;
    final userId = AuthState.instance.user?.id;
    if (userId == null) return;
    if (ApiClient.instance.token == null) return;

    _attached = true;
    _backoffSeconds = 2;
    await _connect();
  }

  /// Tear down the WS connection. Safe to call from anywhere including
  /// hot-restart / logout paths.
  void detach() {
    _attached = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.sink.close();
    } catch (_) {
      // Sink already closed — ignore.
    }
    _socket = null;
    _socketId = null;
  }

  Future<void> _connect() async {
    final endpoint = '${AppEnv.wsUrl}/app/${AppEnv.wsAppKey}'
        '?protocol=7&client=mcare&version=1.0.0&flash=false';
    try {
      _socket = WebSocketChannel.connect(Uri.parse(endpoint));
    } catch (e) {
      _scheduleReconnect(e);
      return;
    }

    _sub = _socket!.stream.listen(
      _onFrame,
      onError: _scheduleReconnect,
      onDone: () => _scheduleReconnect('closed'),
      cancelOnError: true,
    );
  }

  void _onFrame(dynamic raw) {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final event = frame['event'] as String? ?? '';

    if (event == 'pusher:connection_established') {
      final data = _decodeInnerData(frame['data']);
      _socketId = data['socket_id'] as String?;
      // Success reset backoff.
      _backoffSeconds = 2;
      _subscribeUserChannels();
      return;
    }

    if (event == 'pusher:error') {
      // Server rejected us; do not tight-loop reconnect.
      _scheduleReconnect('pusher:error');
      return;
    }

    // App events use `broadcastAs()` names — see backend/app/Events.
    if (event == 'vital.alert') {
      SessionPoller.instance.triggerNow();
    }
  }

  Future<void> _subscribeUserChannels() async {
    final userId = AuthState.instance.user?.id;
    if (userId == null || _socketId == null) return;

    await _subscribe('private-user.$userId');
    await _subscribe('private-care-team.$userId');
  }

  Future<void> _subscribe(String channelName) async {
    final auth = await _authorizeChannel(channelName);
    if (auth == null || _socket == null) return;
    _socket!.sink.add(jsonEncode({
      'event': 'pusher:subscribe',
      'data': {
        'auth': auth,
        'channel': channelName,
      },
    }));
  }

  /// Fetches a per-channel auth signature from Laravel's
  /// `/broadcasting/auth` endpoint. Returns null on failure so the caller
  /// silently skips subscription rather than crashing the app.
  Future<String?> _authorizeChannel(String channelName) async {
    final token = ApiClient.instance.token;
    if (token == null || _socketId == null) return null;

    final authUrl = _broadcastingAuthUrl();
    if (authUrl == null) return null;

    try {
      final resp = await http.post(
        Uri.parse(authUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        body: {
          'socket_id': _socketId!,
          'channel_name': channelName,
        },
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['auth'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Derives the `/broadcasting/auth` URL from the API base
  /// (e.g. `http://host/api/v1` → `http://host/broadcasting/auth`).
  String? _broadcastingAuthUrl() {
    final api = AppEnv.apiBaseUrl;
    // Strip anything after (and including) `/api/`.
    final apiIndex = api.indexOf('/api/');
    final root = apiIndex >= 0 ? api.substring(0, apiIndex) : api;
    if (root.isEmpty) return null;
    return '$root/broadcasting/auth';
  }

  void _scheduleReconnect(Object? error) {
    if (!_attached) return;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    _socketId = null;

    if (kDebugMode) {
      debugPrint('[RealtimeChannel] reconnecting in ${_backoffSeconds}s ($error)');
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), _connect);
    // Cap the backoff so we don't wait forever after a long outage.
    _backoffSeconds = (_backoffSeconds * 2).clamp(2, 60);
  }

  Map<String, dynamic> _decodeInnerData(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return const {};
  }
}
