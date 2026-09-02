import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import '../api/api_client.dart';
import '../env/app_env.dart';
import '../env/runtime_config.dart';
import 'pulse_watcher.dart';
import 'session_poller.dart';

/// README §7.1 primary real-time channel.
///
/// Speaks the Pusher wire protocol (compatible with Laravel Reverb) as a
/// pure-Dart WebSocket client — no native deps, works on web + mobile +
/// desktop from one implementation.
///
/// The endpoint comes from [RuntimeConfig] — the API tells the app where its
/// own broadcaster listens — with a `--dart-define` still winning where a
/// build pinned one. It used to come from the define alone, which meant any
/// build launched without the flags ran with no live connection at all and
/// nobody could tell from the outside.
///
/// [PulseWatcher] carries the same domain invalidations over a cheap cursor
/// poll as a continuous correctness watchdog, and both feed [changes]. A
/// screen therefore cannot be live on one transport and stale on the other.
///
/// `session.changed` events carry domain names only. They trigger the same
/// authenticated REST hydration path used by polling, while independently
/// loaded screens can listen to [changes]. Legacy `vital.alert` frames remain
/// supported during deployment upgrades.
class RealtimeChannel {
  RealtimeChannel._() {
    // The fallback publishes into the same stream as the socket, so every
    // screen already listening for live changes keeps working unchanged when
    // there is no socket to listen to. The channel is a process-lifetime
    // singleton, so this subscription is never torn down.
    PulseWatcher.instance.changes.listen(_changes.add);
    // A stale cursor means the server can no longer name what was missed.
    // Broadcast a wildcard invalidation so independently loaded detail pages
    // refresh too; a role-session refresh alone cannot cover those endpoints.
    PulseWatcher.instance.gaps.listen((_) => _changes.add(const {'*'}));
  }
  static final RealtimeChannel instance = RealtimeChannel._();

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _refreshDebounce;
  String? _socketId;
  bool _attached = false;
  bool _subscribed = false;
  bool _everSubscribed = false;
  int _backoffSeconds = 2;
  final Set<String> _requiredChannels = {};
  final Set<String> _confirmedChannels = {};
  final Set<String> _pendingDomains = {};
  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast(sync: true);

  /// True only after every required private channel is authorised and Reverb
  /// confirms the subscriptions. The cursor watcher remains a lightweight
  /// correctness watchdog even while this is true.
  bool get isSubscribed => _attached && _subscribed;

  /// Domain-level invalidation stream for screens that own an endpoint outside
  /// the role session payload (analytics, announcements, consent flows, etc.).
  Stream<Set<String>> get changes => _changes.stream;

  /// Connect if realtime is enabled and a user is signed in. Idempotent —
  /// calling repeatedly with the same session is a no-op.
  Future<void> attach() async {
    if (!RuntimeConfig.instance.socketEnabled) return;
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
    final wasSubscribed = _subscribed;
    _attached = false;
    _subscribed = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.sink.close();
    } catch (_) {
      // Sink already closed — ignore.
    }
    _socket = null;
    _socketId = null;
    _requiredChannels.clear();
    _confirmedChannels.clear();
    _pendingDomains.clear();
    if (wasSubscribed) {
      SessionPoller.instance.onRealtimeStatusChanged();
    }
  }

  Future<void> _connect() async {
    _subscribed = false;
    _requiredChannels.clear();
    _confirmedChannels.clear();
    final base = RuntimeConfig.instance.socketUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final endpoint =
        '$base/app/${RuntimeConfig.instance.socketAppKey}'
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

    if (event == 'pusher:ping') {
      _socket?.sink.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
      return;
    }

    if (event == 'pusher:connection_established') {
      final data = _decodeInnerData(frame['data']);
      _socketId = data['socket_id'] as String?;
      // Success reset backoff.
      _backoffSeconds = 2;
      unawaited(_subscribeUserChannels());
      return;
    }

    if (event == 'pusher_internal:subscription_succeeded') {
      final channel = frame['channel'] as String?;
      if (channel != null) _confirmedChannels.add(channel);
      if (_requiredChannels.isNotEmpty &&
          _confirmedChannels.containsAll(_requiredChannels)) {
        final reconnect = _everSubscribed;
        _everSubscribed = true;
        _subscribed = true;
        SessionPoller.instance.onRealtimeStatusChanged(refresh: reconnect);
      }
      return;
    }

    if (event == 'pusher_internal:subscription_error') {
      _scheduleReconnect('subscription error');
      return;
    }

    if (event == 'pusher:error') {
      // Server rejected us; do not tight-loop reconnect.
      _scheduleReconnect('pusher:error');
      return;
    }

    // App events use `broadcastAs()` names — see backend/app/Events.
    if (event == 'vital.alert' || event == 'session.changed') {
      final payload = _decodeInnerData(frame['data']);
      final domains = payload['domains'];
      if (domains is List) {
        _pendingDomains.addAll(domains.whereType<String>());
      } else if (event == 'vital.alert') {
        _pendingDomains.addAll(const ['vitals', 'alerts', 'notifications']);
      }
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
        if (_pendingDomains.isNotEmpty) {
          _changes.add(Set.unmodifiable(_pendingDomains));
          _pendingDomains.clear();
        }
        SessionPoller.instance.triggerNow();
      });
    }
  }

  Future<void> _subscribeUserChannels() async {
    final userId = AuthState.instance.user?.id;
    if (userId == null || _socketId == null) return;

    final role = AuthState.instance.user?.role;
    _requiredChannels
      ..clear()
      ..addAll([
        'private-user.$userId',
        'private-app',
        if (role == UserRole.admin || role == UserRole.mcareAssistant)
          'private-staff',
      ]);

    for (final channel in _requiredChannels) {
      final subscribed = await _subscribe(channel);
      if (!subscribed) {
        _scheduleReconnect('channel authorization failed');
        return;
      }
    }
  }

  Future<bool> _subscribe(String channelName) async {
    final auth = await _authorizeChannel(channelName);
    if (auth == null || _socket == null) return false;
    _socket!.sink.add(
      jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'auth': auth, 'channel': channelName},
      }),
    );
    return true;
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
      final resp = await http
          .post(
            Uri.parse(authUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
            body: {'socket_id': _socketId!, 'channel_name': channelName},
          )
          .timeout(const Duration(seconds: 5));
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
    final wasSubscribed = _subscribed;
    _subscribed = false;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    _socketId = null;
    _requiredChannels.clear();
    _confirmedChannels.clear();
    _pendingDomains.clear();

    if (wasSubscribed) {
      SessionPoller.instance.onRealtimeStatusChanged();
    }

    if (kDebugMode) {
      debugPrint(
        '[RealtimeChannel] reconnecting in ${_backoffSeconds}s ($error)',
      );
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
