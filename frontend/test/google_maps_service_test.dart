import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/env/app_env.dart';
import 'package:mcare/core/location/google_maps_service.dart';

void main() {
  test(
    'Google Maps search and directions URLs use the key-free API format',
    () {
      final search = GoogleMapsService.searchUri(0.3476, 32.5825);
      final directions = GoogleMapsService.directionsUri(0.3476, 32.5825);

      expect(search.isScheme('https'), isTrue);
      expect(search.host, 'www.google.com');
      expect(search.queryParameters['api'], '1');
      expect(search.queryParameters['query'], '0.3476,32.5825');
      expect(directions.queryParameters['destination'], '0.3476,32.5825');
    },
  );

  test('external providers fail closed in an unconfigured build', () {
    expect(AppEnv.firebaseEnabled, isFalse);
    expect(AppEnv.embeddedGoogleMapsEnabled, isFalse);
    expect(AppEnv.isConfiguredValue('REPLACE_WITH_FIREBASE_APP_ID'), isFalse);
    expect(AppEnv.isConfiguredValue('DEFAULT_API_KEY'), isFalse);
  });
}
