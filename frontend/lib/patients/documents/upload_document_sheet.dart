import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/widgets/document_upload_form.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'package:flutter/material.dart';

/// The patient adding a document to their own record.
///
/// The form is shared with the staff-side sheet — see [DocumentUploadForm].
/// The two were separate files carrying two copies of the same picker, the
/// same validation and the same file chooser, differing only in where they
/// posted and which category they defaulted to.
class UploadDocumentSheet {
  UploadDocumentSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Upload document',
      subtitle: 'Add lab results, prescriptions, imaging and more.',
      child: DocumentUploadForm(
        initialCategory: DocumentCategory.labResult,
        onSubmit:
            ({
              required file,
              required title,
              required category,
              required fileType,
              required sizeBytes,
              description,
            }) => DocumentsState.instance.uploadDocument(
              file: file,
              title: title,
              category: category,
              fileType: fileType,
              sizeBytes: sizeBytes,
              description: description,
            ),
<<<<<<< Updated upstream
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
=======
      ),
>>>>>>> Stashed changes
    );
  }
}
