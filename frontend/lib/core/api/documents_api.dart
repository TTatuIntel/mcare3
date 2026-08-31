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

class DocumentsApi {
  DocumentsApi._();
  static final DocumentsApi instance = DocumentsApi._();

  String patientStreamPath(String documentId) =>
      '/patient/documents/$documentId/stream';

  String doctorStreamPath({
    required String patientUserId,
    required String documentId,
  }) => '/doctor/patients/$patientUserId/documents/$documentId/stream';

  /// Base path for acting on another user's documents as staff.
  ///
  /// Admin and mCare assistants are not on a caseload, so the doctor routes
  /// reject them outright — the role has to pick the prefix, not the caller.
  String staffDocumentsBase(String patientUserId) {
    final role = AuthState.instance.user?.role;
    final isAdminSide =
        role == UserRole.admin || role == UserRole.mcareAssistant;

    return isAdminSide
        ? '/admin/patients/$patientUserId/documents'
        : '/doctor/patients/$patientUserId/documents';
  }

  /// The signed-in patient's own documents.
  ///
  /// Everything used to arrive through the one session payload, so a document
  /// a doctor had just filed could only be picked up by refetching the whole
  /// record. This is the list the documents screen actually needs.
  Future<List<MedicalDocument>> listMine() async {
    if (!AppEnv.backendEnabled) return const [];

    final res = await ApiClient.instance.get('/patient/documents');
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

  Future<MedicalDocument?> createWithFile({
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? sharedWithDoctorId,
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
      '/patient/documents',
      fields: fields,
      files: [multipart],
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  Future<MedicalDocument?> update({
    required String documentId,
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
      '/patient/documents/$documentId',
      fields: fields,
      files: files,
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

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
      '${staffDocumentsBase(patientUserId)}/$documentId',
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
      '${staffDocumentsBase(patientUserId)}/$documentId/decline-removal',
      body: {'reason': reason},
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  Future<String?> downloadUrl(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get('/patient/documents/$id/download');
    return res['data']?['url'] as String?;
  }

  Future<MedicalDocument?> uploadForPatient({
    required String patientUserId,
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final fields = PatientDomainMapper.documentMetaToApi(
      title: title,
      category: category,
      fileType: fileType,
      description: description,
    ).map((k, v) => MapEntry(k, v.toString()));

    final multipart = await MultipartFileBuilder.fromPlatformFile(file);
    final res = await ApiClient.instance.postMultipart(
      staffDocumentsBase(patientUserId),
      fields: fields,
      files: [multipart],
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  Future<MedicalDocument?> doctorUpdate({
    required String patientUserId,
    required String documentId,
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
      '/doctor/patients/$patientUserId/documents/$documentId',
      fields: fields,
      files: files,
    );
    final json = res['data']?['document'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentFromApi(json);
  }

  Future<String?> doctorDownloadUrl({
    required String patientUserId,
    required String documentId,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get(
      '/doctor/patients/$patientUserId/documents/$documentId/download',
    );
    return res['data']?['url'] as String?;
  }

  Future<bool> doctorDelete({
    required String patientUserId,
    required String documentId,
  }) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete(
      '/doctor/patients/$patientUserId/documents/$documentId',
    );
    return true;
  }
}
