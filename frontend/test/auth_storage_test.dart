import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/services/auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AuthStorage.clear();
  });

  tearDown(() async {
    await AuthStorage.clear();
  });

  test('remembered session survives clearing a tab-scoped session', () async {
    final expiry = DateTime.now().toUtc().add(const Duration(days: 30));
    await AuthStorage.save(
      token: 'remembered-token',
      user: const {'id': '1', 'email': 'user@example.com'},
      remember: true,
      expiresAt: expiry,
    );

    await AuthStorage.clearUnremembered();
    final restored = await AuthStorage.read();

    expect(restored?.token, 'remembered-token');
    expect(restored?.remember, isTrue);
    expect(restored?.expiresAt, expiry);
  });

  test('temporary session ends when the browser session ends', () async {
    await AuthStorage.save(
      token: 'tab-token',
      user: const {'id': '1', 'email': 'user@example.com'},
      remember: false,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 8)),
    );

    await AuthStorage.clearUnremembered();

    expect(await AuthStorage.read(), isNull);
  });

  test('expired remembered session is discarded locally', () async {
    await AuthStorage.save(
      token: 'expired-token',
      user: const {'id': '1', 'email': 'user@example.com'},
      remember: true,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );

    expect(await AuthStorage.read(), isNull);
    expect(await AuthStorage.hasRemembered(), isFalse);
  });
}
