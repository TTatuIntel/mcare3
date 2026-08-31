import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../models/document.dart';
import '../services/doctor_patient_detail_service.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';

/// Files a document into a patient's record on their behalf.
///
/// Shared by doctors and admin staff: DocumentsApi picks the route from the
/// signed-in role, because admin staff are not on a caseload and the doctor
/// endpoints reject them outright. Lives in shared/ rather than doctors/ so the
/// admin surfaces can reach it without importing across role layers.
class StaffUploadDocumentSheet {
  StaffUploadDocumentSheet._();

  static Future<void> show(BuildContext context, {required String patientId, required String patientName}) {
    return GlassSheet.show(
      context,
      title: 'Upload document',
      subtitle: 'For $patientName',
      child: _Form(patientId: patientId, patientName: patientName),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.patientId, required this.patientName});
  final String patientId;
  final String patientName;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  DocumentCategory _category = DocumentCategory.consultationNote;
  bool _saving = false;

  String? _selectedFileName;
  int _selectedFileBytes = 0;
  DocumentFileType _detectedFileType = DocumentFileType.pdf;
  PlatformFile? _pickedFile;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final ext = (file.extension ?? '').toLowerCase();
    final fileType = switch (ext) {
      'pdf' => DocumentFileType.pdf,
      'jpg' || 'jpeg' || 'png' => DocumentFileType.image,
      'doc' || 'docx' => DocumentFileType.doc,
      _ => DocumentFileType.other,
    };
    setState(() {
      _pickedFile = file;
      _selectedFileName = file.name;
      _selectedFileBytes = file.size;
      _detectedFileType = fileType;
      if (_title.text.trim().isEmpty) {
        final nameWithoutExt = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        _title.text = nameWithoutExt;
      }
    });
  }

  Future<void> _upload() async {
    if (_title.text.trim().isEmpty) {
      AppToast.warn(context, 'Enter a document title.');
      return;
    }
    if (_selectedFileName == null || _pickedFile == null) {
      AppToast.warn(context, 'Choose a file to upload.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (AppEnv.backendEnabled) {
        await DocumentsApi.instance.uploadForPatient(
          patientUserId: widget.patientId,
          file: _pickedFile!,
          title: _title.text.trim(),
          category: _category,
          fileType: _detectedFileType,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        );
        await DoctorPatientDetailService.instance.loadPatient(widget.patientId);
      } else {
        StaffState.instance.addDocumentForPatient(
          StaffPatientDocument(
            id: 'sdoc_${DateTime.now().millisecondsSinceEpoch}',
            patientId: widget.patientId,
            title: _title.text.trim(),
            category: _category.label,
            fileType: _detectedFileType,
            uploadedAt: DateTime.now(),
            uploadedBy: 'Doctor',
            // Mock parity with the server: anything staff file is clinical, so
            // it carries the same no-delete protection offline as online.
            source: DocumentSource.clinician,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not upload: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Document uploaded for ${widget.patientName}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _selectedFileName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Title',
          hint: 'e.g. Consultation note — June 2026',
          controller: _title,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Category', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        InputDecorator(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          child: DropdownButton<DocumentCategory>(
            value: _category,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: DocumentCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Notes (optional)',
          controller: _description,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.lg),
        // File picker
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hasFile
                  ? AppPalette.successSoft(context)
                  : AppPalette.surfaceMuted(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: hasFile ? AppColors.success : AppPalette.border(context),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasFile ? AppIcons.check : AppIcons.document,
                  color: hasFile ? AppColors.success : AppPalette.textMuted(context),
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFile ? _selectedFileName! : 'Choose file',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasFile ? AppColors.success : AppPalette.ink(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasFile && _selectedFileBytes > 0)
                        Text(
                          _sizeLabel(_selectedFileBytes),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        )
                      else
                        Text(
                          'PDF, image, or Word document',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasFile)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: AppPalette.textMuted(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _selectedFileName = null;
                      _selectedFileBytes = 0;
                      _pickedFile = null;
                    }),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Upload',
          icon: AppIcons.document,
          loading: _saving,
          expand: true,
          onPressed: _upload,
        ),
      ],
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
