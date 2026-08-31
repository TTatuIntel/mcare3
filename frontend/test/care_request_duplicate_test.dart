import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/models/care_provider.dart';
import 'package:mcare/shared/state/care_state.dart';

/// One open request per provider, enforced on the client so the button can be
/// trusted. The API enforces the same rule — see PatientCareRequestTest.
void main() {
  const provider = CareProvider(
    id: 'p1',
    name: 'Dr. Kojo Mensah',
    specialty: 'Internal medicine',
    facility: 'Aga Khan Hospital, Nairobi',
    yearsExperience: 12,
    rating: 4.8,
    totalReviews: 240,
  );

  CareRequest requestFor(CareProvider p, CareRequestStatus status) =>
      CareRequest(
        id: 'r1',
        providerId: p.id,
        providerName: p.name,
        providerSpecialty: p.specialty,
        createdAt: DateTime(2026, 8, 30),
        status: status,
      );

  setUp(() {
    CareState.instance.seed(providers: const [], requests: const []);
  });

  test('a pending request is found for the provider it names', () {
    CareState.instance.seed(
      providers: const [provider],
      requests: [requestFor(provider, CareRequestStatus.pending)],
    );

    expect(CareState.instance.hasPendingRequest('p1'), isTrue);
    expect(CareState.instance.hasPendingRequest('p2'), isFalse);
  });

  test('requesting the same provider twice adds no second request', () {
    CareState.instance.seed(providers: const [provider], requests: const []);

    CareState.instance.requestCare(provider);
    CareState.instance.requestCare(provider);

    expect(CareState.instance.requests.length, 1);
  });

  test('a closed request does not block asking again', () {
    for (final closed in [
      CareRequestStatus.cancelled,
      CareRequestStatus.rejected,
    ]) {
      CareState.instance.seed(
        providers: const [provider],
        requests: [requestFor(provider, closed)],
      );

      expect(CareState.instance.hasPendingRequest('p1'), isFalse);
      CareState.instance.requestCare(provider);
      expect(CareState.instance.requests.length, 2);
    }
  });

  test('requestCareRemote refuses a duplicate before it reaches the API', () {
    CareState.instance.seed(
      providers: const [provider],
      requests: [requestFor(provider, CareRequestStatus.pending)],
    );

    expect(
      () => CareState.instance.requestCareRemote(provider),
      throwsA(isA<DuplicateCareRequest>()),
    );
  });

  test('requestCareRemote refuses a provider already on the team', () {
    const assigned = CareProvider(
      id: 'p9',
      name: 'Dr. Sarah Adeyemi',
      specialty: 'Endocrinology',
      facility: 'Nairobi Hospital',
      yearsExperience: 9,
      rating: 4.7,
      totalReviews: 165,
      assigned: true,
    );
    CareState.instance.seed(providers: const [assigned], requests: const []);

    expect(
      () => CareState.instance.requestCareRemote(assigned),
      throwsA(isA<AlreadyOnCareTeam>()),
    );
  });
}
