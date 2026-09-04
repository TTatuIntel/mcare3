import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../models/document.dart';

class DocumentsState extends ChangeNotifier {
  DocumentsState._();
  static final DocumentsState instance = DocumentsState._();

  final List<MedicalDocument> _items = [];
  List<MedicalDocument> get all => List.unmodifiable(_items);

  void seed(List<MedicalDocument> items) {
    _items
      ..clear()
      ..addAll(items)
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    notifyListeners();
  }

  void add(MedicalDocument doc) {
    _items.insert(0, doc);
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void rename(String id, String title) {
    replaceLocal(
      id,
      _items.firstWhere((d) => d.id == id).copyWith(title: title),
    );
  }

  void replaceLocal(String id, MedicalDocument updated) {
    final i = _items.indexWhere((d) => d.id == id);
    if (i == -1) return;
    _items[i] = updated;
    notifyListeners();
  }

  Future<MedicalDocument> updateDocument({
    required String id,
    String? title,
    DocumentCategory? category,
    DocumentFileType? fileType,
    String? description,
    PlatformFile? file,
  }) async {
    final i = _items.indexWhere((d) => d.id == id);
    if (i == -1) throw StateError('Document not found');
    final original = _items[i];

    if (!AppEnv.backendEnabled) {
      final next = original.copyWith(
        title: title,
        category: category,
        fileType: fileType,
        description: description?.isEmpty == true ? null : description,
        sizeBytes: file?.size ?? original.sizeBytes,
      );
      replaceLocal(id, next);
      return next;
    }

    final saved = await DocumentsApi.instance.update(
      documentId: id,
      title: title,
      category: category,
      fileType: fileType,
      description: description,
      file: file,
    );
    if (saved == null) throw StateError('Update failed');
    _items[i] = saved;
    notifyListeners();
    return saved;
  }

  List<MedicalDocument> filter(DocumentCategory? c) {
    if (c == null) return all;
    return _items.where((d) => d.category == c).toList();
  }

  /// Uploads document metadata + file blob to the API.
  Future<MedicalDocument> uploadDocument({
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? sharedWithDoctorId,
    int sizeBytes = 0,
  }) async {
    final draft = MedicalDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      category: category,
      fileType: fileType,
      sizeBytes: sizeBytes > 0 ? sizeBytes : file.size,
      uploadedAt: DateTime.now(),
      uploadedBy: 'You',
      description: description,
      sharedWithDoctorId: sharedWithDoctorId,
    );

    if (!AppEnv.backendEnabled) {
      add(draft);
      return draft;
    }

    final saved = await DocumentsApi.instance.createWithFile(
      file: file,
      title: title,
      category: category,
      fileType: fileType,
      description: description,
      sharedWithDoctorId: sharedWithDoctorId,
    );
    final canonical = saved ?? draft;
    _items.insert(0, canonical);
    notifyListeners();
    return canonical;
  }

  /// Persisting variant of [remove]. DELETEs the document on the server,
  /// then removes from local state. Rolls back on failure.
  Future<void> deleteDocument(String id) async {
    final i = _items.indexWhere((d) => d.id == id);
    if (i == -1) return;
    final original = _items[i];
    _items.removeAt(i);
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      await DocumentsApi.instance.delete(id);
    } catch (e) {
      _items.insert(i, original);
      notifyListeners();
      rethrow;
    }
  }
}
