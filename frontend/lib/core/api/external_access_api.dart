import 'package:file_picker/file_picker.dart';

import '../env/app_env.dart';
import 'api_client.dart';
import 'multipart_file_builder.dart';

/// A patient-generated external access link/code for outside doctors.
class ExternalAccessLink {
  const ExternalAccessLink({
    required this.id,
    required this.label,
    required this.accessCode,
    required this.url,
    required this.token,
    required this.expiresAt,
    required this.active,
    this.revokedAt,
  });

  final String id;
  final String label;
  final String? accessCode;
  final String? url;
  final String token;
  final DateTime expiresAt;
  final bool active;
  final DateTime? revokedAt;

  static ExternalAccessLink fromApi(Map<String, dynamic> json) {
    return ExternalAccessLink(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Emergency access',
      accessCode: json['access_code'] as String?,
      url: json['url'] as String?,
      token: json['token'] as String? ?? '',
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.now(),
      active: json['active'] as bool? ?? false,
      revokedAt: json['revoked_at'] != null
          ? DateTime.tryParse(json['revoked_at'] as String)
          : null,
    );
  }
}

/// Patient-side management of external access links + the external portal's
/// record-update endpoints (vitals, meds, documents).
class ExternalAccessApi {
  ExternalAccessApi._();
  static final ExternalAccessApi instance = ExternalAccessApi._();

  Future<List<ExternalAccessLink>> list() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/external-access');
    final items = res['data']?['links'] as List? ?? [];
    return items
        .map(
          (e) => ExternalAccessLink.fromApi((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<ExternalAccessLink?> create({
    String? label,
    int expiresInHours = 24,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/external-access',
      body: {
        if (label != null && label.isNotEmpty) 'label': label,
        'expires_in_hours': expiresInHours,
      },
    );
    final json = res['data']?['link'] as Map?;
    if (json == null) return null;
    return ExternalAccessLink.fromApi(json.cast<String, dynamic>());
  }

  Future<void> revoke(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/patient/external-access/$id/revoke');
  }

  /// External doctor: exchange a spoken access code for the portal token.
  Future<String?> resolveCode(String code) async {
    final res = await ApiClient.instance.post(
      '/external/resolve-code',
      body: {'code': code},
      allowWhenBackendDisabled: true,
    );
    return res['data']?['token'] as String?;
  }

  /// External doctor: record a vital reading against the patient.
  Future<void> recordVital(
    String token, {
    required String vitalKey,
    required double value,
    double? secondaryValue,
    String? note,
    String? doctorName,
  }) async {
    await ApiClient.instance.post(
      '/external/$token/vitals',
      body: {
        'vital_key': vitalKey,
        'value': value,
        if (secondaryValue != null) 'secondary_value': secondaryValue,
        if (note != null && note.isNotEmpty) 'note': note,
        if (doctorName != null && doctorName.isNotEmpty)
          'doctor_name': doctorName,
      },
      allowWhenBackendDisabled: true,
    );
  }

  /// External doctor: assign a medication / prescription.
  Future<void> assignMedication(
    String token, {
    required String name,
    required String dosage,
    required String frequency,
    String? form,
    String? instructions,
    String? startDate,
    String? endDate,
    String? doctorName,
  }) async {
    await ApiClient.instance.post(
      '/external/$token/medications',
      body: {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        if (form != null && form.isNotEmpty) 'form': form,
        if (instructions != null && instructions.isNotEmpty)
          'instructions': instructions,
        if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
        if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
        if (doctorName != null && doctorName.isNotEmpty)
          'doctor_name': doctorName,
      },
      allowWhenBackendDisabled: true,
    );
  }

  /// External doctor: upload a document or clinical report.
  Future<void> uploadDocument(
    String token, {
    required PlatformFile file,
    required String title,
    required String category,
    required String fileType,
    String? description,
    String? doctorName,
  }) async {
    final multipart = await MultipartFileBuilder.fromPlatformFile(file);
    await ApiClient.instance.postMultipart(
      '/external/$token/documents',
      fields: {
        'title': title,
        'category': category,
        'file_type': fileType,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (doctorName != null && doctorName.isNotEmpty)
          'doctor_name': doctorName,
      },
      files: [multipart],
      allowWhenBackendDisabled: true,
    );
  }
}
