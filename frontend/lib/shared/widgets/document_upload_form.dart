import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/document.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'app_text_field.dart';
import 'app_toast.dart';

/// A file the user chose, with what the app worked out about it.
class PickedDocument {
  const PickedDocument({
    required this.file,
    required this.fileType,
    required this.name,
    required this.sizeBytes,
  });

  final PlatformFile file;
  final DocumentFileType fileType;
  final String name;
  final int sizeBytes;
}

/// Choosing a document to upload, in one place.
///
/// The extension list and the extension-to-type mapping used to be copied into
/// each upload sheet, and both copies read `pdf, jpg, jpeg, png, doc, docx` —
/// the set a web form imagines, not the set a hospital produces. A photo taken
/// on any current iPhone is HEIC; a scan off a hospital MFP is TIFF; a monitor
/// export is CSV. Every one of those was refused by the picker before the
/// server ever saw it, so a patient trying to upload their own X-ray was told
/// their file did not exist.
class DocumentFilePicker {
  DocumentFilePicker._();

  /// Kept in step with `MedicalDocumentFiles::ALLOWED_EXTENSIONS` on the
  /// server. The picker is a convenience, not the gate — the server validates
  /// independently — but offering a file it will reject wastes an upload, and
  /// refusing one it would accept is worse.
  static const allowedExtensions = <String>[
    'pdf',
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff',
    'doc', 'docx', 'odt', 'rtf', 'txt',
    'xls', 'xlsx', 'csv',
  ];

  /// A human-readable summary for the picker's hint line.
  static const summary = 'PDF, photo or scan, Word, or spreadsheet';

  static DocumentFileType typeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      'pdf' => DocumentFileType.pdf,
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'webp' ||
      'heic' ||
      'heif' ||
      'bmp' ||
      'tif' ||
      'tiff' => DocumentFileType.image,
      'doc' || 'docx' || 'odt' || 'rtf' => DocumentFileType.doc,
      _ => DocumentFileType.other,
    };
  }

  static Future<PickedDocument?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      // Needed on web, where there is no path to read back from.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;

    return PickedDocument(
      file: file,
      fileType: typeForExtension(file.extension ?? ''),
      name: file.name,
      sizeBytes: file.size,
    );
  }

  /// The filename without its extension, used to pre-fill an empty title.
  static String titleFrom(String filename) => filename.contains('.')
      ? filename.substring(0, filename.lastIndexOf('.'))
      : filename;

  static String sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The upload form itself — title, category, description, file, submit.
///
/// One widget for both the patient uploading their own document and staff
/// filing one into a patient's record. Those were two files that had drifted
/// only in their default category and their submit call, while carrying two
/// copies of the same picker, the same validation and the same 90-line file
/// chooser between them.
class DocumentUploadForm extends StatefulWidget {
  const DocumentUploadForm({
    super.key,
    required this.initialCategory,
    required this.onSubmit,
    this.submitLabel = 'Upload',
    this.successMessage = 'Document uploaded.',
  });

  final DocumentCategory initialCategory;

  /// Performs the upload. Throwing surfaces the message to the user and leaves
  /// the sheet open with everything they typed intact.
  final Future<void> Function({
    required PlatformFile file,
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    required int sizeBytes,
    String? description,
  })
  onSubmit;

  final String submitLabel;
  final String successMessage;

  @override
  State<DocumentUploadForm> createState() => _DocumentUploadFormState();
}

class _DocumentUploadFormState extends State<DocumentUploadForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late DocumentCategory _category = widget.initialCategory;
  bool _saving = false;
  PickedDocument? _picked;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await DocumentFilePicker.pick();
    if (picked == null || !mounted) return;

    setState(() {
      _picked = picked;
      if (_title.text.trim().isEmpty) {
        _title.text = DocumentFilePicker.titleFrom(picked.name);
      }
    });
  }

  Future<void> _submit() async {
    final picked = _picked;
    if (_title.text.trim().isEmpty) {
      AppToast.warn(context, 'Enter a document title.');
      return;
    }
    if (picked == null) {
      AppToast.warn(context, 'Choose a file to upload.');
      return;
    }

    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      await widget.onSubmit(
        file: picked.file,
        title: _title.text.trim(),
        category: _category,
        fileType: picked.fileType,
        sizeBytes: picked.sizeBytes,
        description: description.isEmpty ? null : description,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not upload: $e');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, widget.successMessage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _picked;

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
            items: _selectableCategories
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
        _FileChooser(
          picked: picked,
          onTap: _pickFile,
          onClear: () => setState(() => _picked = null),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: widget.submitLabel,
          icon: AppIcons.document,
          loading: _saving,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }

  /// Every category except the two the server issues.
  ///
  /// A report is filed automatically when the care team signs one off; letting
  /// someone hand-label an upload as one would put a document in the Reports
  /// list that nobody issued and nobody signed.
  List<DocumentCategory> get _selectableCategories => DocumentCategory.values
      .where((c) => !c.isIssuedReport || c == widget.initialCategory)
      .toList(growable: false);
}

class _FileChooser extends StatelessWidget {
  const _FileChooser({
    required this.picked,
    required this.onTap,
    required this.onClear,
  });

  final PickedDocument? picked;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = picked != null;

    return GestureDetector(
      onTap: onTap,
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
              color: hasFile
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
                    hasFile ? picked!.name : 'Choose file',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasFile
                          ? AppColors.success
                          : AppPalette.ink(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hasFile && picked!.sizeBytes > 0
                        ? DocumentFilePicker.sizeLabel(picked!.sizeBytes)
                        : DocumentFilePicker.summary,
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
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
