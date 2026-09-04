import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/medical_document_viewer_body.dart';
import 'edit_document_sheet.dart';

class DocumentViewerSheet {
  DocumentViewerSheet._();

  static Future<void> show(BuildContext context, MedicalDocument doc) {
    return GlassSheet.show(
      context,
      title: doc.title,
      subtitle: '${doc.category.label} · ${doc.sizeLabel}',
      maxHeightFactor: 0.92,
      child: _Viewer(doc: doc),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.doc});
  final MedicalDocument doc;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late MedicalDocument _doc;
  int _previewReload = 0;

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
  }

  Future<void> _edit() async {
    final updated = await EditDocumentSheet.show(context, doc: _doc);
    if (updated != true || !mounted) return;
    final matches =
        DocumentsState.instance.all.where((d) => d.id == _doc.id);
    if (matches.isNotEmpty) {
      setState(() {
        _doc = matches.first;
        _previewReload++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MedicalDocumentViewerBody(
      documentId: _doc.id,
      fileType: _doc.fileType,
<<<<<<< Updated upstream
=======
      documentTitle: _doc.title,
      // What the server recorded the file to be, so View and Download hand
      // over the real thing rather than a `.bin` guessed from `fileType`.
      mimeType: _doc.mimeType,
      downloadName: _doc.downloadName,
>>>>>>> Stashed changes
      hasFile: _doc.hasFile,
      previewReloadToken: _previewReload,
      metaRows: [
        DocumentMetaRow(
          label: 'Uploaded',
          value: DateFormat.yMMMd().format(_doc.uploadedAt),
        ),
        DocumentMetaRow(label: 'By', value: _doc.uploadedBy),
        if (_doc.description != null)
          DocumentMetaRow(label: 'Notes', value: _doc.description!),
      ],
      onEdit: _edit,
      onDelete: () => DocumentsState.instance.deleteDocument(_doc.id),
    );
  }
}
