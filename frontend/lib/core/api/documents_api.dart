import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../shared/models/document.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'multipart_file_builder.dart';
import 'patient_domain_mapper.dart';

/// Every route that reads or writes a medical document.
///
/// One method per operation, with `patientUserId` deciding whose record is
/// being acted on rather than a second near-identical method per caller. The
/// class previously carried both — `update` and `doctorUpdate`, `delete` and
/// `doctorDelete`, `downloadUrl` and `doctorDownloadUrl` — differing only in a
/// hardcoded path prefix. Half of those were already dead, and the surviving
/// halves had begun to diverge in what they parsed out of the response, which
/// is how a patient and their doctor came to see different fields for the same
/// row.
class DocumentsApi {
  DocumentsApi._();
  static final DocumentsApi instance = DocumentsApi._();

  /// Base path for acting on a patient's documents.
  ///
  /// [patientUserId] null means the signed-in patient's own record. Otherwise
  /// the caller is staff, and the role picks the prefix: admin and mCare
  /// assistants are not on a caseload, so the doctor routes reject them
  /// outright.
  String _base([String? patientUserId]) {
    if (patientUserId == null) return '/patient/documents';

    final role = AuthState.instance.user?.role;
    final isAdminSide =
        role == UserRole.admin || role == UserRole.mcareAssistant;

    return isAdminSide
        ? '/admin/patients/$patientUserId/documents'
        : '/doctor/patients/$patientUserId/documents';
  }

  String patientStreamPath(String documentId) =>
      '/patient/documents/$documentId/stream';

  String doctorStreamPath({
    required String patientUserId,
    required String documentId,
  }) => '/doctor/patients/$patientUserId/documents/$documentId/stream';

  /// The signed-in patient's own documents.
  ///
  /// Everything used to arrive through the one session payload, so a document
  /// a doctor had just filed could only be picked up by refetching the whole
  /// record. This is the list the documents screen actually needs.
  Future<List<MedicalDocument>> listMine() => _list(null);

  /// A patient's documents as their care team sees them.
  ///
  /// The dossier carries these too, but reloading a whole chart to find out
  /// whether one file arrived is not a refresh anyone performs — so a clinician
  /// watching for the result they asked the patient to upload had no way to see
  /// it land.
  Future<List<MedicalDocument>> listForPatient(
    String patientUserId, {
    bool removalRequestedOnly = false,
  }) => _list(patientUserId, removalRequestedOnly: removalRequestedOnly);

  Future<List<MedicalDocument>> _list(
    String? patientUserId, {
    bool removalRequestedOnly = false,
  }) async {
    if (!AppEnv.backendEnabled) return const [];

    final query = removalRequestedOnly ? '?removal_requested=1' : '';
    final res = await ApiClient.instance.get('${_base(patientUserId)}$query');
    final list = res['data']?['documents'] as List? ?? const [];

    return list
        .map(
          (e) => PatientDomainMapper.documentFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<Uint8List> fetchBytes({
    required String documentId,
    String? patientUserId,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled.');
    }
    final path = patientUserId != null
        ? doctorStreamPath(patientUserId: patientUserId, documentId: documentId)
        : patientStreamPath(documentId);
    return ApiClient.instance.getBytes(path);
  }

  /// Files a document into a record.
  ///
  /// [patientUserId] null uploads to the signed-in patient's own record;
  /// otherwise staff are filing into someone else's. The server marks the
  /// provenance accordingly — which is what decides, later, whether it can ever
  /// be deleted — so the caller does not have to say.
  Future<MedicalDocument?> create({
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? sharedWithDoctorId,
    String? patientUserId,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final fields = PatientDomainMapper.documentMetaToApi(
      title: title,
      category: category,
      fileType: fileType,
      description: description,
      sharedWithDoctorId: sharedWithDoctorId,
    ).map((k, v) => MapEntry(k, v.toString()));

    final multipart = await MultipartFileBuilder.fromPlatformFile(file);
    final res = await ApiClient.instance.postMultipart(
      _base(patientUserId),
      fields: fields,
      files: [multipart],
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  Future<MedicalDocument?> update({
    required String documentId,
    String? patientUserId,
    String? title,
    DocumentCategory? category,
    DocumentFileType? fileType,
    String? description,
    PlatformFile? file,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final fields = <String, String>{};
    if (title != null) fields['title'] = title;
    if (category != null) fields['category'] = category.name;
    if (fileType != null) fields['file_type'] = fileType.name;
    if (description != null) fields['description'] = description;

    final files = file == null
        ? <http.MultipartFile>[]
        : [await MultipartFileBuilder.fromPlatformFile(file)];

    final res = await ApiClient.instance.patchMultipart(
      '${_base(patientUserId)}/$documentId',
      fields: fields,
      files: files,
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  /// The patient deleting one of their own uploads. Everything else in the
  /// record is refused by the server — see [requestRemoval].
  Future<bool> delete(String id) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete('/patient/documents/$id');
    return true;
  }

  /// Ask the care team to take a clinician-filed document out of the record.
  ///
  /// The patient cannot delete one themselves and should not be able to, but a
  /// result filed against the wrong person is theirs to get removed. This
  /// request is what authorises a staff-side deletion at all.
  Future<MedicalDocument?> requestRemoval({
    required String documentId,
    required String reason,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/documents/$documentId/request-removal',
      body: {'reason': reason},
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  /// Withdraw a removal request before staff have answered it.
  Future<bool> cancelRemovalRequest(String documentId) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete(
      '/patient/documents/$documentId/request-removal',
    );
    return true;
  }

  /// Staff honour a removal the patient asked for.
  ///
  /// The only delete anywhere in a patient's record, and the server refuses it
  /// without a standing request — the authority is the patient's, not the
  /// caller's role, so both staff routes go through the same check.
  Future<bool> honourRemoval({
    required String patientUserId,
    required String documentId,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete(
      '${_base(patientUserId)}/$documentId',
      body: {if (note != null && note.isNotEmpty) 'note': note},
    );
    return true;
  }

  /// Staff refuse a removal request, with a reason the patient reads.
  Future<MedicalDocument?> declineRemoval({
    required String patientUserId,
    required String documentId,
    required String reason,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '${_base(patientUserId)}/$documentId/decline-removal',
      body: {'reason': reason},
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  /// The addressable URL for a document's bytes, with the name and type the
  /// server holds for it.
  Future<({String? url, String? downloadName, String? mimeType})> downloadUrl(
    String id, {
    String? patientUserId,
  }) async {
    if (!AppEnv.backendEnabled) {
      return (url: null, downloadName: null, mimeType: null);
    }
    final res = await ApiClient.instance.get(
      '${_base(patientUserId)}/$id/download',
    );
    final data = res['data'] as Map?;
    return (
      url: data?['url'] as String?,
      downloadName: data?['download_name'] as String?,
      mimeType: data?['mime_type'] as String?,
    );
  }

  /// Answers a patient's document request with the file, closing the request
  /// in the same call.
  ///
  /// Uploading and closing are one act, so they are one request. Splitting
  /// them left a filed document sitting beside a request still reading
  /// "waiting" whenever the second call was lost — which is exactly the state
  /// a patient reads as "nobody has done anything".
  ///
  /// Returns the filed document and the closed request together.
  Future<({MedicalDocument? document, Map<String, dynamic>? request})>
  fulfilDocumentRequest({
    required String requestId,
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return (document: null, request: null);

    final fields = PatientDomainMapper.documentMetaToApi(
      title: title,
      category: category,
      fileType: fileType,
      description: description,
    ).map((k, v) => MapEntry(k, v.toString()));
    if (note != null && note.isNotEmpty) fields['note'] = note;

    final res = await ApiClient.instance.postMultipart(
      '/doctor/document-requests/$requestId/fulfill',
      fields: fields,
      files: [await MultipartFileBuilder.fromPlatformFile(file)],
    );

    final docJson = res['data']?['document'] as Map<String, dynamic>?;
    return (
      document: docJson == null
          ? null
          : PatientDomainMapper.documentFromApi(docJson),
      request: (res['data']?['request'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
