import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/async/request_cache.dart';

void main() {
  setUp(RequestCache.instance.clear);
  tearDown(RequestCache.instance.clear);

  test('collapses identical concurrent reads into one fetch', () async {
    var calls = 0;
    Future<int> fetch() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 7;
    }

    final results = await Future.wait([
      RequestCache.instance.read('k', fetch),
      RequestCache.instance.read('k', fetch),
      RequestCache.instance.read('k', fetch),
    ]);

    expect(results, [7, 7, 7]);
    expect(calls, 1, reason: 'three callers, one request');
  });

  test('serves a repeat read from memory inside the ttl', () async {
    var calls = 0;
    Future<int> fetch() async => ++calls;

    expect(await RequestCache.instance.read('k', fetch), 1);
    expect(await RequestCache.instance.read('k', fetch), 1);
    expect(calls, 1);
  });

  test('refetches once the ttl has passed', () async {
    var calls = 0;
    Future<int> fetch() async => ++calls;

    await RequestCache.instance
        .read('k', fetch, ttl: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await RequestCache.instance
        .read('k', fetch, ttl: const Duration(milliseconds: 30));

    expect(calls, 2);
  });

  test('forceRefresh bypasses a live entry', () async {
    var calls = 0;
    Future<int> fetch() async => ++calls;

    await RequestCache.instance.read('k', fetch);
    await RequestCache.instance.read('k', fetch, forceRefresh: true);
    expect(calls, 2);
  });

  test('a failure is not cached and does not strand the in-flight slot',
      () async {
    var calls = 0;
    Future<int> failing() async {
      calls++;
      throw StateError('boom');
    }

    await expectLater(
      RequestCache.instance.read('k', failing),
      throwsStateError,
    );
    expect(RequestCache.instance.inFlightCount, 0, reason: 'slot released');
    expect(RequestCache.instance.entryCount, 0, reason: 'error not cached');

    await expectLater(
      RequestCache.instance.read('k', failing),
      throwsStateError,
    );
    expect(calls, 2, reason: 'retried rather than replaying the failure');
  });

  test('invalidate and invalidatePrefix drop the right entries', () async {
    await RequestCache.instance.read('GET /a', () async => 1);
    await RequestCache.instance.read('GET /b', () async => 2);
    expect(RequestCache.instance.entryCount, 2);

    RequestCache.instance.invalidate('GET /a');
    expect(RequestCache.instance.peek<int>('GET /a'), isNull);
    expect(RequestCache.instance.peek<int>('GET /b'), 2);

    RequestCache.instance.invalidatePrefix('GET ');
    expect(RequestCache.instance.entryCount, 0);
  });
}
