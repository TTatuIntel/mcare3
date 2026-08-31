import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google sign-in needs the same OAuth client ID on both sides: the app asks
/// Google for a token with that audience, and the API refuses any token whose
/// `aud` is not its own `GOOGLE_CLIENT_ID`.
///
/// Two IDs that merely look alike fail at the very last step, with a server
/// log line ("Google token audience mismatch") and a generic failure in the
/// UI — so the mismatch is cheap to introduce and expensive to diagnose. This
/// catches it at test time instead. It found a real one: a VS Code launch
/// configuration pinned a different client ID from the API's.
///
/// Both files are gitignored local configuration, so the test skips rather
/// than fails when either is absent.
void main() {
  final backendEnv = File('../backend/.env');
  final appConfig = File('config/app_config.local.json');

  String? envValue(String key) {
    if (!backendEnv.existsSync()) return null;
    for (final line in backendEnv.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final at = trimmed.indexOf('=');
      if (at <= 0 || trimmed.substring(0, at).trim() != key) continue;
      return trimmed.substring(at + 1).trim().replaceAll('"', '');
    }
    return null;
  }

  Map<String, dynamic>? config() {
    if (!appConfig.existsSync()) return null;
    return jsonDecode(appConfig.readAsStringSync()) as Map<String, dynamic>;
  }

  bool isPlaceholder(String? value) =>
      value == null ||
      value.trim().isEmpty ||
      value.startsWith('REPLACE_') ||
      value.startsWith('YOUR_');

  test('the app and the API agree on one Google OAuth client ID', () {
    final apiClientId = envValue('GOOGLE_CLIENT_ID');
    final appClientId = config()?['MCARE_GOOGLE_CLIENT_ID'] as String?;

    if (isPlaceholder(apiClientId) || isPlaceholder(appClientId)) {
      markTestSkipped('Google sign-in is not configured locally.');
      return;
    }

    expect(
      appClientId,
      apiClientId,
      reason:
          'MCARE_GOOGLE_CLIENT_ID in frontend/config/app_config.local.json '
          'must match GOOGLE_CLIENT_ID in backend/.env, or every Google '
          'sign-in is rejected by the API as an audience mismatch.',
    );
  });

  test('the server client ID matches too, so native builds verify', () {
    final apiClientId = envValue('GOOGLE_CLIENT_ID');
    final serverClientId =
        config()?['MCARE_GOOGLE_SERVER_CLIENT_ID'] as String?;

    if (isPlaceholder(apiClientId) || isPlaceholder(serverClientId)) {
      markTestSkipped('Google sign-in is not configured locally.');
      return;
    }

    // Android and iOS ask Google for a token addressed to the *server* client
    // so the Laravel verifier can check it. A different value here breaks the
    // native apps while leaving web working, which reads as a platform bug.
    expect(serverClientId, apiClientId);
  });

  test('every launch configuration loads the shared config file', () {
    final launch = File('.vscode/launch.json');
    if (!launch.existsSync()) {
      markTestSkipped('No launch.json in this checkout.');
      return;
    }

    // Strip // comments — launch.json is JSONC.
    final raw = launch
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final configs =
        (jsonDecode(raw) as Map<String, dynamic>)['configurations'] as List;

    for (final entry in configs.cast<Map<String, dynamic>>()) {
      final name = entry['name'] as String;
      final args = (entry['args'] as List? ?? const []).cast<String>();

      // A configuration that hardcodes a client ID drifts from the API the
      // moment either is rotated. The config file is the one source.
      expect(
        args.any((a) => a.startsWith('--dart-define=MCARE_GOOGLE_CLIENT_ID=')),
        isFalse,
        reason: '"$name" pins its own Google client ID instead of using '
            'config/app_config.local.json',
      );

      // Mock builds have no backend and no OAuth, so they need no config.
      final isMock = args.any(
        (a) => a == '--dart-define=MCARE_USE_BACKEND=false',
      );
      if (isMock) continue;

      expect(
        args.any((a) => a.startsWith('--dart-define-from-file=')),
        isTrue,
        reason: '"$name" would build without any social sign-in credentials',
      );
    }
  });
}
