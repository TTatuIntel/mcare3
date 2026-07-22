import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../shared/models/document.dart';
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
  }) =>
      '/doctor/patients/$patientUserId/documents/$documentId/stream';

  Future<Uint8List> fetchBytes({
    required String documentId,
    String? patientUserId,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled.');
    }
    final path = patientUserId != null
        ? doctorStreamPath(
            patientUserId: patientUserId,
            documentId: documentId,
          )
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
      '/doctor/patients/$patientUserId/documents',
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
