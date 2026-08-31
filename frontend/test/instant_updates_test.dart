import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/core/env/runtime_config.dart';
import 'package:mcare/core/realtime/pulse_watcher.dart';
import 'package:mcare/core/realtime/realtime_channel.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';

/// A change on the server has to reach the screen without being asked for.
///
/// The socket does that where one is running. These cover the path that has
/// to work everywhere else — the change cursor — because that is what decides
/// whether a deployment with no Reverb server shows an alert in seconds or
/// only when somebody pulls to refresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Answers `/me/pulse` from a script, one entry per call.
  void serve(List<Map<String, dynamic>> answers) {
    var call = 0;
    ApiClient.instance.setTransportForTesting(
      MockClient((request) async {
        if (!request.url.path.endsWith('/me/pulse')) {
          return http.Response('{"success":true,"data":{}}', 200);
        }
        final body = answers[call.clamp(0, answers.length - 1)];
        call++;
        return http.Response(
          jsonEncode({'success': true, 'data': body}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
  }

  Map<String, dynamic> answer({
    required int cursor,
    List<String> domains = const [],
    bool stale = false,
  }) => {
    'cursor': cursor,
    'domains': domains,
    'stale': stale,
    'retention_minutes': 15,
    'server_time': DateTime.now().toIso8601String(),
  };

  setUp(() {
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000001',
        firstName: 'Test',
        lastName: 'User',
        email: 'test@mcare.health',
        role: UserRole.patient,
      ),
    );
    ApiClient.instance.setToken('test-token');
    PulseWatcher.instance.reset();
    RuntimeConfig.instance.resetForTesting();
  });

  tearDown(() {
    PulseWatcher.instance.reset();
    RuntimeConfig.instance.resetForTesting();
    ApiClient.instance.setTransportForTesting(null);
    ApiClient.instance.setToken(null);
    AuthState.instance.signOut();
  });

  test('the first answer only sets a baseline, it does not replay', () async {
    serve([
      answer(cursor: 40, domains: const ['alerts']),
    ]);

    final seen = <Set<String>>[];
    final sub = PulseWatcher.instance.changes.listen(seen.add);

    await PulseWatcher.instance.poll();

    expect(PulseWatcher.instance.cursor, 40);
    expect(seen, isEmpty, reason: 'the screen just loaded this data over REST');
    await sub.cancel();
  });

  test('a change after the baseline is reported and advances the cursor', () async {
    serve([
      answer(cursor: 40),
      answer(cursor: 44, domains: const ['alerts', 'notifications']),
    ]);

    final seen = <Set<String>>[];
    final sub = PulseWatcher.instance.changes.listen(seen.add);

    await PulseWatcher.instance.poll(); // baseline
    await PulseWatcher.instance.poll(); // the alert lands

    expect(seen, hasLength(1));
    expect(seen.single, containsAll(<String>['alerts', 'notifications']));
    expect(PulseWatcher.instance.cursor, 44);
    await sub.cancel();
  });

  test('a live change reaches the same stream the socket feeds', () async {
    serve([
      answer(cursor: 40),
      answer(cursor: 41, domains: const ['vitals']),
    ]);

    // Screens listen here through RealtimeRefreshMixin and must not care
    // which transport noticed the change.
    final seen = <Set<String>>[];
    final sub = RealtimeChannel.instance.changes.listen(seen.add);

    await PulseWatcher.instance.poll();
    await PulseWatcher.instance.poll();

    expect(seen.single, contains('vitals'));
    await sub.cancel();
  });

  test('a cursor the server can no longer account for raises a gap', () async {
    serve([
      answer(cursor: 40),
      answer(cursor: 90, stale: true),
    ]);

    var gaps = 0;
    final sub = PulseWatcher.instance.gaps.listen((_) => gaps++);

    await PulseWatcher.instance.poll();
    await PulseWatcher.instance.poll();

    expect(gaps, 1, reason: 'the listener has to re-read rather than trust a list');
    await sub.cancel();
  });

  test('the cursor never moves backwards', () async {
    serve([
      answer(cursor: 40),
      answer(cursor: 44, domains: const ['alerts']),
      answer(cursor: 12, domains: const ['alerts']),
    ]);

    await PulseWatcher.instance.poll();
    await PulseWatcher.instance.poll();
    await PulseWatcher.instance.poll();

    expect(PulseWatcher.instance.cursor, 44);
  });

  test('an unreachable server is survived, not thrown from', () async {
    ApiClient.instance.setTransportForTesting(
      MockClient((_) async => http.Response('nope', 500)),
    );

    await PulseWatcher.instance.poll();

    expect(PulseWatcher.instance.cursor, 0);
  });

  test('watching stops with the session', () async {
    serve([answer(cursor: 40)]);

    PulseWatcher.instance.start();
    expect(PulseWatcher.instance.isRunning, isTrue);

    PulseWatcher.instance.stop();
    expect(PulseWatcher.instance.isRunning, isFalse);
  });

  test('signing out forgets where the last session had read up to', () async {
    serve([answer(cursor: 40)]);
    await PulseWatcher.instance.poll();
    expect(PulseWatcher.instance.cursor, 40);

    AuthState.instance.signOut();

    expect(PulseWatcher.instance.cursor, 0);
    expect(PulseWatcher.instance.isRunning, isFalse);
  });

  group('the socket endpoint comes from the server', () {
    test('a deployment that runs one is used', () {
      RuntimeConfig.instance.applyForTesting(
        socketUrl: 'ws://192.168.1.20:8080',
        socketAppKey: 'abc123',
      );

      expect(RuntimeConfig.instance.socketEnabled, isTrue);
      expect(RuntimeConfig.instance.socketUrl, 'ws://192.168.1.20:8080');
    });

    test('a deployment that runs none leaves the pulse to carry it', () {
      RuntimeConfig.instance.applyForTesting();

      expect(RuntimeConfig.instance.socketEnabled, isFalse);
      expect(RuntimeConfig.instance.socketUrl, isEmpty);
    });

    test('the poll cadence the server names is honoured, within reason', () {
      RuntimeConfig.instance.applyForTesting(
        pulseInterval: const Duration(seconds: 3),
      );

      expect(RuntimeConfig.instance.pulseInterval, const Duration(seconds: 3));
    });
  });
}
