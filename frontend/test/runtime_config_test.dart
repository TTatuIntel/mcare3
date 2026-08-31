import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/core/auth/apple_sign_in_service.dart';
import 'package:mcare/core/auth/google_sign_in_service.dart';
import 'package:mcare/core/env/app_env.dart';
import 'package:mcare/core/env/runtime_config.dart';

/// These run with no `--dart-define` at all, which is the situation that
/// produced the bug: an app built by any path that forgot the flag told every
/// user that Google sign-in was unavailable, while the credential sat in
/// backend/.env the whole time.
///
/// The client ID now comes from the API that verifies the tokens, so the two
/// cannot disagree and no build flag is required for it to work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void respondWith(Object body, {int status = 200}) {
    ApiClient.instance.setTransportForTesting(
      MockClient(
        (req) async => http.Response(
          jsonEncode(body),
          status,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
  }

  Map<String, Object?> payload({
    String google = '',
    String apple = '',
    String appleRedirect = '',
  }) => {
    'success': true,
    'data': {
      'google': {'client_id': google, 'enabled': google.isNotEmpty},
      'apple': {
        'client_id': apple,
        'redirect_uri': appleRedirect,
        'enabled': apple.isNotEmpty,
      },
    },
  };

  setUp(RuntimeConfig.instance.resetForTesting);

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    RuntimeConfig.instance.resetForTesting();
  });

  test('this build pins no client ID of its own', () {
    // If this ever fails the rest of the file proves nothing: the compile-time
    // value would be masking whatever the server said.
    expect(AppEnv.isConfiguredValue(AppEnv.googleClientId), isFalse);
  });

  test('a build with no dart-define is configured by the API', () async {
    expect(GoogleSignInService.instance.isConfigured, isFalse);

    respondWith(payload(google: '99343549279-abc.apps.googleusercontent.com'));
    await RuntimeConfig.instance.load();

    expect(GoogleSignInService.instance.isConfigured, isTrue);
    expect(
      RuntimeConfig.instance.googleClientId,
      '99343549279-abc.apps.googleusercontent.com',
    );
  });

  test('native builds address the token to the same client the API checks', () {
    RuntimeConfig.instance.applyForTesting(
      googleClientId: '99343549279-abc.apps.googleusercontent.com',
    );

    // A server client ID that differed from the audience the API accepts is
    // what makes a token get rejected after an otherwise successful sign-in.
    expect(
      RuntimeConfig.instance.googleServerClientId,
      RuntimeConfig.instance.googleClientId,
    );
  });

  test('an API with no Google credential leaves sign-in unavailable', () async {
    respondWith(payload());
    await RuntimeConfig.instance.load();

    expect(GoogleSignInService.instance.isConfigured, isFalse);
  });

  test('an unreachable API never crashes launch', () async {
    ApiClient.instance.setTransportForTesting(
      MockClient((req) async => throw const SocketExceptionStub()),
    );

    await expectLater(RuntimeConfig.instance.load(), completes);
    expect(GoogleSignInService.instance.isConfigured, isFalse);
  });

  test('an older API without /config is survivable', () async {
    respondWith({'message': 'Not Found'}, status: 404);

    await expectLater(RuntimeConfig.instance.load(), completes);
    expect(GoogleSignInService.instance.isConfigured, isFalse);
  });

  test('Apple needs both its client ID and a redirect to count', () async {
    respondWith(payload(apple: 'com.tattuintel.mcare.web'));
    await RuntimeConfig.instance.load();
    expect(
      AppleSignInService.instance.isConfigured,
      isFalse,
      reason: 'a Services ID with nowhere to return to cannot complete',
    );

    RuntimeConfig.instance.applyForTesting(
      appleClientId: 'com.tattuintel.mcare.web',
      appleRedirectUri: 'https://app.matendocare.com/',
    );
    expect(AppleSignInService.instance.isConfigured, isTrue);
  });
}

/// A throwing transport, without depending on dart:io in a test that also
/// needs to run on the web target.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
