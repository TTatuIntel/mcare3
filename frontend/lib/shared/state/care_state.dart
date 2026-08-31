import 'package:flutter/foundation.dart';

import '../../core/api/care_api.dart';
import '../../core/env/app_env.dart';
import '../models/care_provider.dart';

class CareState extends ChangeNotifier {
  CareState._();
  static final CareState instance = CareState._();

  final List<CareProvider> _providers = [];
  final List<CareRequest> _requests = [];

  List<CareProvider> get all => List.unmodifiable(_providers);
  List<CareProvider> get assigned =>
      _providers.where((p) => p.assigned).toList();
  List<CareProvider> get available =>
      _providers.where((p) => !p.assigned).toList();
  List<CareRequest> get requests => List.unmodifiable(_requests);

  /// The still-open request for [providerId], if the patient already has one.
  ///
  /// One open request per provider is the rule everywhere: the browse list
  /// reads this to show "Requested" instead of a second call to action, and
  /// [requestCareRemote] reads it to refuse a duplicate outright.
  CareRequest? pendingRequestFor(String providerId) {
    for (final r in _requests) {
      if (r.providerId == providerId && r.status == CareRequestStatus.pending) {
        return r;
      }
    }
    return null;
  }

  bool hasPendingRequest(String providerId) =>
      pendingRequestFor(providerId) != null;

  void seed({
    required List<CareProvider> providers,
    required List<CareRequest> requests,
  }) {
    _providers
      ..clear()
      ..addAll(providers);
    _requests
      ..clear()
      ..addAll(requests);
    notifyListeners();
  }

  void requestCare(CareProvider p, {String? reason}) {
    final open = pendingRequestFor(p.id);
    if (open != null) return;
    _requests.insert(
      0,
      CareRequest(
        id: 'r_${DateTime.now().millisecondsSinceEpoch}',
        providerId: p.id,
        providerName: p.name,
        providerSpecialty: p.specialty,
        createdAt: DateTime.now(),
        status: CareRequestStatus.pending,
        reason: reason,
      ),
    );
    notifyListeners();
  }

  void cancelRequest(String id) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i == -1) return;
    final r = _requests[i];
    _requests[i] = CareRequest(
      id: r.id,
      providerId: r.providerId,
      providerName: r.providerName,
      providerSpecialty: r.providerSpecialty,
      createdAt: r.createdAt,
      status: CareRequestStatus.cancelled,
      reason: r.reason,
    );
    notifyListeners();
  }

  /// Persisting variant of [requestCare]. POSTs to the API and inserts the
  /// server-canonical row.
  ///
  /// Throws [DuplicateCareRequest] when this provider already has an open
  /// request. The API enforces the same rule — this only spares the round trip
  /// and gives the sheet something specific to say.
  Future<CareRequest> requestCareRemote(
    CareProvider p, {
    String? reason,
  }) async {
    final open = pendingRequestFor(p.id);
    if (open != null) throw DuplicateCareRequest(p.name, open);
    if (p.assigned) throw AlreadyOnCareTeam(p.name);

    if (!AppEnv.backendEnabled) {
      requestCare(p, reason: reason);
      return _requests.first;
    }
    final saved = await CareApi.instance.requestProvider(
      providerId: p.id,
      reason: reason,
    );
    final canonical =
        saved ??
        CareRequest(
          id: 'r_${DateTime.now().millisecondsSinceEpoch}',
          providerId: p.id,
          providerName: p.name,
          providerSpecialty: p.specialty,
          createdAt: DateTime.now(),
          status: CareRequestStatus.pending,
          reason: reason,
        );
    // The API answers a duplicate with the request that already exists, so
    // match on id before inserting — otherwise a stale local copy would be
    // listed twice.
    final existing = _requests.indexWhere((r) => r.id == canonical.id);
    if (existing >= 0) {
      _requests[existing] = canonical;
    } else {
      _requests.insert(0, canonical);
    }
    notifyListeners();
    return canonical;
  }

  /// Persisting variant of [cancelRequest].
  Future<void> cancelRequestRemote(String id) async {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i == -1) return;
    final original = _requests[i];
    cancelRequest(id);
    if (!AppEnv.backendEnabled) return;
    try {
      final saved = await CareApi.instance.cancelRequest(id);
      if (saved != null) {
        final j = _requests.indexWhere((r) => r.id == id);
        if (j >= 0) _requests[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _requests[i] = original;
      notifyListeners();
      rethrow;
    }
  }
}

/// Raised when a patient tries to request a provider they already have an open
/// request with. Carries the existing request so callers can point at it.
class DuplicateCareRequest implements Exception {
  const DuplicateCareRequest(this.providerName, this.existing);

  final String providerName;
  final CareRequest existing;

  @override
  String toString() =>
      'You already have a pending request with $providerName.';
}

/// Raised when the provider is already on the patient's care team.
class AlreadyOnCareTeam implements Exception {
  const AlreadyOnCareTeam(this.providerName);

  final String providerName;

  @override
  String toString() => '$providerName is already on your care team.';
}
