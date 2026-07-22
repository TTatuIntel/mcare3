import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class UploadDocumentSheet {
  UploadDocumentSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Upload document',
      subtitle: 'Add lab results, prescriptions, imaging and more.',
      child: const _Form(),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  DocumentCategory _category = DocumentCategory.labResult;
  bool _saving = false;

  String? _selectedFileName;
  int _selectedFileBytes = 0;
  DocumentFileType _detectedFileType = DocumentFileType.other;
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
      // Pre-fill title from filename if still empty
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
      await DocumentsState.instance.uploadDocument(
        file: _pickedFile!,
        title: _title.text.trim(),
        category: _category,
        fileType: _detectedFileType,
        sizeBytes: _selectedFileBytes,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not upload: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Document uploaded.');
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
          hint: 'e.g. HbA1c Lab Result',
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
          label: 'Description (optional)',
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
