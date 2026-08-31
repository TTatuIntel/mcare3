import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/medical_document_viewer_body.dart';
import 'document_removal_request_block.dart';
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
      documentTitle: _doc.title,
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
      // Editing and deleting are offered only on the patient's own uploads.
      // A document their care team filed, and above all an issued report, is
      // part of the record — showing controls the server would refuse just
      // teaches people the app is broken.
      onEdit: _doc.canDelete ? _edit : null,
      onDelete: _doc.canDelete
          ? () => DocumentsState.instance.deleteDocument(_doc.id)
          : null,
      // What the patient can do about a document they cannot delete. Refusing
      // the delete was only half an answer — the other half is the route to
      // getting a document removed that should never have been filed on them.
      footer: DocumentRemovalRequestBlock(
        document: _doc,
        onChanged: (updated) => setState(() => _doc = updated),
      ),
    );
  }
}
