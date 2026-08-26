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
  Future<CareRequest> requestCareRemote(
    CareProvider p, {
    String? reason,
  }) async {
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
    _requests.insert(0, canonical);
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
