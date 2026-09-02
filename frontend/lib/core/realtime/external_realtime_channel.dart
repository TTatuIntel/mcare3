import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../env/app_env.dart';
import '../env/runtime_config.dart';

/// Token-scoped private realtime channel for the one-patient guest portal.
/// Events contain invalidation metadata only; the portal always re-reads the
/// canonical, token-authorized REST resource.
class ExternalRealtimeChannel {
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pulseTimer;
  String? _token;
  String? _channelName;
  VoidCallback? _onChanged;
  bool _attached = false;
  bool _pulseInFlight = false;
  bool _pulseBaselined = false;
  int _pulseCursor = 0;
  int _pulseFailures = 0;
  int _backoffSeconds = 2;

  Future<void> attach({
    required String token,
    required String channelName,
    required VoidCallback onChanged,
  }) async {
    if (_attached && _token == token && _channelName == channelName) return;
    detach();
    _attached = true;
    _token = token;
    _channelName = channelName;
    _onChanged = onChanged;
    _startPulse();
    if (RuntimeConfig.instance.socketEnabled) {
      await _connect();
    }
  }

  void detach() {
    _attached = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    _token = null;
    _channelName = null;
    _onChanged = null;
    _pulseInFlight = false;
    _pulseBaselined = false;
    _pulseCursor = 0;
    _pulseFailures = 0;
    _backoffSeconds = 2;
  }

  void _startPulse() {
    unawaited(_pollPulse());
    _schedulePulse();
  }

  void _schedulePulse() {
    _pulseTimer?.cancel();
    if (!_attached) return;
    final penalty = _pulseFailures.clamp(0, 4);
    _pulseTimer = Timer(
      RuntimeConfig.instance.pulseInterval * (1 << penalty),
      () async {
        await _pollPulse();
        _schedulePulse();
      },
    );
  }

  Future<void> _pollPulse() async {
    final token = _token;
    if (!_attached || _pulseInFlight || token == null) return;

    _pulseInFlight = true;
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppEnv.apiBaseUrl}/external/${Uri.encodeComponent(token)}'
              '/pulse?since=$_pulseCursor',
            ),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404 || response.statusCode == 410) {
        _onChanged?.call();
        return;
      }
      if (response.statusCode != 200) throw StateError('pulse unavailable');

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;

      _pulseFailures = 0;
      final cursor = int.tryParse('${data['cursor'] ?? ''}') ?? _pulseCursor;
      final wasFirst = !_pulseBaselined;
      final startedFromEmpty = _pulseBaselined && _pulseCursor == 0;
      _pulseBaselined = true;
      if (cursor > _pulseCursor) _pulseCursor = cursor;
      if (wasFirst) return;

      final domains = data['domains'] as List?;
      if (data['stale'] == true ||
          (startedFromEmpty && cursor > 0) ||
          (domains != null && domains.isNotEmpty)) {
        _onChanged?.call();
      }
    } catch (_) {
      _pulseFailures++;
    } finally {
      _pulseInFlight = false;
    }
  }

  Future<void> _connect() async {
    if (!_attached) return;
    final base = RuntimeConfig.instance.socketUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final endpoint =
        '$base/app/${RuntimeConfig.instance.socketAppKey}'
        '?protocol=7&client=mcare-external&version=1.0.0&flash=false';
    try {
      _socket = WebSocketChannel.connect(Uri.parse(endpoint));
      _subscription = _socket!.stream.listen(
        _onFrame,
        onError: _scheduleReconnect,
        onDone: () => _scheduleReconnect('closed'),
        cancelOnError: true,
      );
    } catch (error) {
      _scheduleReconnect(error);
    }
  }

  Future<void> _onFrame(dynamic raw) async {
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
      final data = _decodeData(frame['data']);
      final socketId = data['socket_id'] as String?;
      if (socketId != null) await _authorizeAndSubscribe(socketId);
      return;
    }
    if (event == 'pusher_internal:subscription_succeeded') {
      _backoffSeconds = 2;
      return;
    }
    if (event == 'session.changed') {
      _onChanged?.call();
      return;
    }
    if (event == 'pusher:error' ||
        event == 'pusher_internal:subscription_error') {
      _scheduleReconnect(event);
    }
  }

  Future<void> _authorizeAndSubscribe(String socketId) async {
    final token = _token;
    final channelName = _channelName;
    if (!_attached || token == null || channelName == null) return;

    try {
      final response = await http
          .post(
            Uri.parse(
              '${AppEnv.apiBaseUrl}/external/${Uri.encodeComponent(token)}'
              '/broadcasting/auth',
            ),
            headers: const {'Accept': 'application/json'},
            body: {'socket_id': socketId, 'channel_name': channelName},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        _scheduleReconnect('authorization ${response.statusCode}');
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final auth = body['auth'] as String?;
      if (auth == null || auth.isEmpty) {
        _scheduleReconnect('authorization response');
        return;
      }
      _socket?.sink.add(
        jsonEncode({
          'event': 'pusher:subscribe',
          'data': {'auth': auth, 'channel': channelName},
        }),
      );
    } catch (error) {
      _scheduleReconnect(error);
    }
  }

  void _scheduleReconnect(Object? _) {
    if (!_attached) return;
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), _connect);
    _backoffSeconds = (_backoffSeconds * 2).clamp(2, 60);
  }

  static Map<String, dynamic> _decodeData(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return const {};
  }
}

typedef VoidCallback = void Function();
