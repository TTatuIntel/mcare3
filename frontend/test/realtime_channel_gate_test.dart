import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/core/env/app_env.dart';
import 'package:mcare/core/realtime/realtime_channel.dart';

/// Guards the README §7.1 opt-in gate: unless both MCARE_WS_URL and
/// MCARE_WS_APP_KEY are set, [RealtimeChannel.attach] must remain a no-op.
/// Locking this in prevents a future refactor from silently making the
/// WebSocket client mandatory (which would break local dev without Reverb).
void main() {
  group('RealtimeChannel opt-in gate', () {
    test('realtime is disabled when no WS URL is configured', () {
      // The compile-time default for MCARE_WS_URL is empty; if a future
      // dev sets a real default here, that would flip realtime on for
      // every user unexpectedly.
      expect(AppEnv.wsUrl, isEmpty);
      expect(AppEnv.wsAppKey, isEmpty);
      expect(AppEnv.realtimeEnabled, isFalse);
    });

    test('attach is a safe no-op without configuration', () async {
      // Should not throw, should not open a socket, should not schedule
      // reconnects. Idempotent to call repeatedly.
      await RealtimeChannel.instance.attach();
      await RealtimeChannel.instance.attach();

      // detach() from clean state must not throw.
      RealtimeChannel.instance.detach();
    });
  });
}
