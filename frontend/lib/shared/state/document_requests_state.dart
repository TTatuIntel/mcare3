import 'package:flutter/foundation.dart';

import '../../core/api/document_requests_api.dart';
import '../../core/env/app_env.dart';
import '../models/document.dart';
import '../models/document_request.dart';

/// Documents the patient has asked their care team to produce.
///
/// The counterpart of [DocumentsState]: that one holds what is in the record,
/// this one holds what has been asked for and is not there yet. Keeping them
/// apart matters on the documents screen — an outstanding request is not a
/// document, and showing it as an empty row in the list would be a lie about
/// what the patient can open.
class DocumentRequestsState extends ChangeNotifier {
  DocumentRequestsState._();
  static final DocumentRequestsState instance = DocumentRequestsState._();

  final List<DocumentRequest> _items = [];

  List<DocumentRequest> get all => List.unmodifiable(_items);

  /// Raised and not yet answered — the ones the documents screen surfaces.
  List<DocumentRequest> get open =>
      _items.where((r) => r.isOpen).toList(growable: false);

  /// Answered one way or the other, newest first.
  List<DocumentRequest> get closed =>
      _items.where((r) => !r.isOpen).toList(growable: false);

  /// Past their needed-by date and still open. Worth saying out loud, because
  /// the patient may need to chase it somewhere other than the app.
  List<DocumentRequest> get overdue =>
      _items.where((r) => r.overdue).toList(growable: false);

  void seed(List<DocumentRequest> items) {
    _items
      ..clear()
      ..addAll(items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!AppEnv.backendEnabled) return;
    seed(await DocumentRequestsApi.instance.listMine());
  }

  Future<DocumentRequest> submit({
    required String title,
    required DocumentCategory category,
    required DocumentRequestTarget target,
    String? note,
    String? targetDoctorId,
    String? targetDoctorName,
    DateTime? neededBy,
    DateTime? periodFrom,
    DateTime? periodTo,
  }) async {
    final draft = DocumentRequest(
      id: 'dreq_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      category: category,
      target: target,
      status: DocumentRequestStatus.pending,
      createdAt: DateTime.now(),
      note: note,
      targetDoctorId: targetDoctorId,
      targetDoctorName: targetDoctorName,
      neededBy: neededBy,
      periodFrom: periodFrom,
      periodTo: periodTo,
    );

    if (!AppEnv.backendEnabled) {
      _items.insert(0, draft);
      notifyListeners();
      return draft;
    }

    final saved = await DocumentRequestsApi.instance.submit(
      title: title,
      category: category,
      target: target,
      note: note,
      targetDoctorId: targetDoctorId,
      neededBy: neededBy,
      periodFrom: periodFrom,
      periodTo: periodTo,
    );
    final canonical = saved ?? draft;
    _items.insert(0, canonical);
    notifyListeners();
    return canonical;
  }

  /// Withdraw a request before the care team has answered it.
  ///
  /// Optimistic, then reconciled: the row is already off the patient's "still
  /// waiting" list by the time the response lands, and rolls back whole if the
  /// server refuses.
  Future<void> cancel(String id) async {
    final i = _items.indexWhere((r) => r.id == id);
    if (i == -1 || !_items[i].isOpen) return;
    final original = _items[i];

    _items[i] = original.copyWith(
      status: DocumentRequestStatus.cancelled,
      resolvedAt: DateTime.now(),
    );
    notifyListeners();

    if (!AppEnv.backendEnabled) return;

    try {
      final saved = await DocumentRequestsApi.instance.cancel(id);
      if (saved != null) {
        final j = _items.indexWhere((r) => r.id == id);
        if (j >= 0) _items[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _items[i] = original;
      notifyListeners();
      rethrow;
    }
  }
}
