// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:printing/printing.dart';

class PdfViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  const PdfViewerScreen({super.key,
    required this.path, required this.title});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _totalPages  = 0;
  int _currentPage = 0;
  bool _isReady    = false;
  PDFViewController? _ctrl;

  Future<void> _sharePdf() async {
    final bytes = await File(widget.path).readAsBytes();
    await Printing.sharePdf(
      bytes: bytes,
      filename: widget.title.endsWith('.pdf')
        ? widget.title : '${widget.title}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13),
          overflow: TextOverflow.ellipsis),
        actions: [
          if (_isReady) ...[
            // Bouton partager
            IconButton(
              icon: const Icon(Icons.share_outlined,
                color: Color(0xFF22D3EE), size: 22),
              tooltip: 'Partager / Télécharger',
              onPressed: _sharePdf),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(
                '${_currentPage + 1} / $_totalPages',
                style: const TextStyle(color: Colors.white70,
                  fontSize: 12, fontWeight: FontWeight.w700)))),
          ],
        ],
      ),
      body: Stack(children: [
        PDFView(
          filePath: widget.path,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          backgroundColor: const Color(0xFF050505),
          onRender: (pages) => setState(() {
            _totalPages = pages ?? 0;
            _isReady    = true;
          }),
          onPageChanged: (page, _) => setState(() =>
            _currentPage = page ?? 0),
          onViewCreated: (ctrl) => _ctrl = ctrl,
          onError: (e) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating)),
        ),
        if (!_isReady)
          const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE))),
      ]),
      bottomNavigationBar: _isReady && _totalPages > 1
        ? Container(
            color: Colors.black.withOpacity(0.6),
            padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
              IconButton(
                onPressed: _currentPage > 0
                  ? () => _ctrl?.setPage(_currentPage - 1) : null,
                icon: Icon(Icons.chevron_left,
                  color: _currentPage > 0
                    ? Colors.white : Colors.grey[700])),
              Text('Page ${_currentPage + 1} / $_totalPages',
                style: const TextStyle(color: Colors.white70,
                  fontSize: 12)),
              IconButton(
                onPressed: _currentPage < _totalPages - 1
                  ? () => _ctrl?.setPage(_currentPage + 1) : null,
                icon: Icon(Icons.chevron_right,
                  color: _currentPage < _totalPages - 1
                    ? Colors.white : Colors.grey[700])),
            ])) : null,
    );
  }
}
