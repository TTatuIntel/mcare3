import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../../shared/models/document.dart';
import '../../shared/services/doctor_patient_detail_service.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class EditDocumentSheet {
  EditDocumentSheet._();

  static Future<bool> show(
    BuildContext context, {
    required MedicalDocument doc,
    String? patientUserId,
  }) async {
    final updated = await GlassSheet.show<bool>(
      context,
      title: 'Edit document',
      subtitle: doc.title,
      child: _Form(doc: doc, patientUserId: patientUserId),
    );
    return updated == true;
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.doc, this.patientUserId});
  final MedicalDocument doc;
  final String? patientUserId;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late DocumentCategory _category;
  bool _saving = false;

  String? _selectedFileName;
  int _selectedFileBytes = 0;
  DocumentFileType? _detectedFileType;
  PlatformFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.doc.title);
    _description = TextEditingController(text: widget.doc.description ?? '');
    _category = widget.doc.category;
  }

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
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      AppToast.warn(context, 'Enter a document title.');
      return;
    }
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      if (!AppEnv.backendEnabled) {
        DocumentsState.instance.replaceLocal(
          widget.doc.id,
          widget.doc.copyWith(
            title: _title.text.trim(),
            category: _category,
            fileType: _detectedFileType ?? widget.doc.fileType,
            description: description.isEmpty ? null : description,
          ),
        );
      } else if (widget.patientUserId != null) {
        await DocumentsApi.instance.update(
          patientUserId: widget.patientUserId!,
          documentId: widget.doc.id,
          title: _title.text.trim(),
          category: _category,
          fileType: _detectedFileType,
          description: description.isEmpty ? '' : description,
          file: _pickedFile,
        );
        await DoctorPatientDetailService.instance.loadDocuments(
          widget.patientUserId!,
        );
      } else {
        await DocumentsState.instance.updateDocument(
          id: widget.doc.id,
          title: _title.text.trim(),
          category: _category,
          fileType: _detectedFileType,
          description: description.isEmpty ? '' : description,
          file: _pickedFile,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    AppToast.success(context, 'Document updated.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNewFile = _selectedFileName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.doc.hasFile) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppPalette.warningSoft(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.warning),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(AppIcons.alert, color: AppColors.warning, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This document has no file yet. Pick a file below to enable preview and download.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(label: 'Title', controller: _title),
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
          label: 'Description (optional)',
          controller: _description,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.lg),
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hasNewFile
                  ? AppPalette.successSoft(context)
                  : AppPalette.surfaceMuted(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: hasNewFile
                    ? AppColors.success
                    : AppPalette.border(context),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasNewFile ? AppIcons.check : AppIcons.upload,
                  color: hasNewFile
                      ? AppColors.success
                      : AppPalette.textMuted(context),
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasNewFile
                            ? _selectedFileName!
                            : widget.doc.hasFile
                            ? 'Replace file (optional)'
                            : 'Attach file (required)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasNewFile
                              ? AppColors.success
                              : AppPalette.ink(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hasNewFile
                            ? _sizeLabel(_selectedFileBytes)
                            : 'PDF, image, or Word document',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasNewFile)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: AppPalette.textMuted(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _selectedFileName = null;
                      _selectedFileBytes = 0;
                      _pickedFile = null;
                      _detectedFileType = null;
                    }),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Save changes',
          icon: AppIcons.check,
          loading: _saving,
          expand: true,
          onPressed: _save,
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
