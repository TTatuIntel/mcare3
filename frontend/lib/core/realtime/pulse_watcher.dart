import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/auth/auth_state.dart';
import '../api/api_client.dart';
import '../env/app_env.dart';
import '../env/runtime_config.dart';

/// The floor under live updates: "what changed since id N?", asked constantly.
///
/// The WebSocket is faster and is always preferred, but it only exists where
/// a Reverb server is running and reachable from the client's network — not
/// on a laptop running the API alone, not behind a proxy that drops upgrades,
/// not for a phone that just lost its connection. Without something else, all
/// of those degraded to re-fetching whole role sessions on a 30-second timer,
/// which is what makes an app feel like it needs a manual refresh.
///
/// So this asks a single indexed question every few seconds. The answer is a
/// cursor and a list of changed *domain names* — no clinical content — and it
/// costs the server one primary-key read when nothing has happened, which is
/// almost always. Screens then re-hydrate through the same authorised REST
/// endpoints they already use, so nothing about authorization changes.
///
/// It stays active as a correctness watchdog even while the socket is
/// connected. A WebSocket subscription can succeed against a Reverb instance
/// whose API publisher is accidentally pointed elsewhere; the cursor makes
/// that deployment error degrade to a short delay instead of stale screens.
class PulseWatcher {
  PulseWatcher._();
  static final PulseWatcher instance = PulseWatcher._();

  /// Emits the data domains the server says changed. Fed into the same stream
  /// screens already listen to for socket events, so a screen cannot be live
  /// on one transport and stale on the other.
  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast(sync: true);
  Stream<Set<String>> get changes => _changes.stream;

  /// Raised when the server says our cursor predates its buffer — changes
  /// happened that it can no longer enumerate, so the listener should do a
  /// full re-read rather than trust a domain list.
  final StreamController<void> _gaps = StreamController<void>.broadcast(
    sync: true,
  );
  Stream<void> get gaps => _gaps.stream;

  Timer? _timer;
  bool _running = false;
  bool _inFlight = false;
  bool _baselined = false;
  int _cursor = 0;
  int _consecutiveFailures = 0;

  /// Where the client has read up to. Zero until the first answer arrives.
  @visibleForTesting
  int get cursor => _cursor;

  bool get isRunning => _running;

  /// Begins watching. Idempotent — calling it again while running does not
  /// restart the cycle or lose the cursor.
  void start() {
    if (!AppEnv.backendEnabled) return;
    if (AuthState.instance.user == null) return;
    if (ApiClient.instance.token == null) return;
    if (_running) return;

    _running = true;
    // Ask immediately: whatever happened while this client was disconnected,
    // asleep, or on another screen should not wait out a first interval.
    unawaited(poll());
    _schedule();
  }

  /// Stops watching and forgets nothing — a restart resumes from the same
  /// cursor, so a gap while the socket was up is still caught up on.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Full reset, for sign-out. The next session starts from a fresh baseline
  /// rather than replaying the previous user's changes.
  void reset() {
    stop();
    _baselined = false;
    _cursor = 0;
    _consecutiveFailures = 0;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;

    // Backing off on repeated failure keeps an offline client from asking a
    // dead server every three seconds for as long as it stays open.
    final base = RuntimeConfig.instance.pulseInterval;
    final penalty = _consecutiveFailures.clamp(0, 4);
    _timer = Timer(base * (1 << penalty), () async {
      await poll();
      _schedule();
    });
  }

  /// One question and its answer. Public so a resumed app or a screen that
  /// just came forward can ask without waiting for the next tick.
  Future<void> poll() async {
    if (!AppEnv.backendEnabled) return;
    if (_inFlight) return;
    if (AuthState.instance.user == null) return;
    if (ApiClient.instance.token == null) return;

    _inFlight = true;
    try {
      final res = await ApiClient.instance
          .get('/me/pulse?since=$_cursor')
          .timeout(const Duration(seconds: 10));
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;

      _consecutiveFailures = 0;

      final cursor = int.tryParse('${data['cursor'] ?? ''}') ?? _cursor;
      // Whether we had a baseline is not the same question as whether the
      // cursor is zero: a client that first asked while the buffer was empty
      // is caught up at zero, and treating that as "not started yet" would
      // silently discard the first changes to arrive after it.
      final wasBaseline = !_baselined;
      final startedFromEmpty = _baselined && _cursor == 0;
      _baselined = true;
      _cursor = cursor > _cursor ? cursor : _cursor;

      // The first answer only establishes where to watch from. The data on
      // screen was just loaded through REST; replaying what happened before
      // the client arrived would be noise.
      if (wasBaseline) return;

      // The buffer was empty when we last looked and is not now. The server
      // answers a zero cursor with a baseline, so it has not told us which
      // domains those rows touched — re-read rather than miss them.
      if (startedFromEmpty && cursor > 0) {
        _gaps.add(null);
        return;
      }

      if (data['stale'] == true) {
        _gaps.add(null);
      }

      final domains = (data['domains'] as List?)
          ?.map((d) => d.toString())
          .where((d) => d.isNotEmpty)
          .toSet();
      if (domains != null && domains.isNotEmpty) {
        _changes.add(Set.unmodifiable(domains));
      }
    } catch (_) {
      // Offline, an older API with no pulse endpoint, or a rate-limit reply.
      // The heavier periodic sweep is still there behind this.
      _consecutiveFailures++;
    } finally {
      _inFlight = false;
    }
  }
}
