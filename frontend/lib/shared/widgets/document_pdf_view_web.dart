import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

Widget buildPdfPreview({required String documentId, required String url}) {
  final viewType = 'mcare-doc-$documentId';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true;
    return iframe;
  });
  return HtmlElementView(viewType: viewType);
}
