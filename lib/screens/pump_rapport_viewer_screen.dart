import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class RapportViewerScreen extends StatelessWidget {
  final Uint8List pdfBytes; // On reçoit directement les octets du fichier
  final String title;

  const RapportViewerScreen({
    Key? key,
    required this.pdfBytes,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.black, // Pour matcher avec le reste de ton app
        elevation: 0,
      ),
      // C'est ici que la magie opère
      body: PdfPreview(
        build: (format) => pdfBytes,
        allowSharing: true, // Laisse le bouton de partage au cas où
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }
}