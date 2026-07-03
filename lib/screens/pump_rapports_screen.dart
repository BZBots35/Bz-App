// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/pdf_storage_service.dart';
import 'pdf_viewer_screen.dart';
import '../widgets/lang_selector.dart';

class PumpRapportsScreen extends StatefulWidget {
  final String? chantierPrefix;
  final String? chantierNom;
  const PumpRapportsScreen({super.key, this.chantierPrefix, this.chantierNom});
  @override
  State<PumpRapportsScreen> createState() => _PumpRapportsScreenState();
}

class _PumpRapportsScreenState extends State<PumpRapportsScreen> {
  final _storage = PdfStorageService();
  List<PdfFile> _pdfs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPdfs();
  }

  Future<void> _loadPdfs() async {
    setState(() => _loading = true);
    final list = await _storage.listPdfs(chantierPrefix: widget.chantierPrefix);
    if (mounted) setState(() { _pdfs = list; _loading = false; });
  }

  Future<void> _deletePdf(PdfFile pdf) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Supprimer ?',
          style: TextStyle(color: Colors.white)),
        content: Text('Supprimer "${pdf.name}" ?',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _storage.deletePdf(pdf.path);
      _loadPdfs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.chantierNom != null
      ? 'Rapports — ${widget.chantierNom}'
      : 'Tous les rapports';

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(title.toUpperCase(),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadPdfs),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : _pdfs.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.picture_as_pdf_outlined,
                color: Colors.grey[700], size: 56),
              const SizedBox(height: 16),
              const Text('Aucun rapport enregistré',
                style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Les rapports PDF seront sauvegardés ici',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]))
          : RefreshIndicator(
              onRefresh: _loadPdfs,
              color: const Color(0xFF22D3EE),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pdfs.length,
                itemBuilder: (_, i) => _buildPdfCard(_pdfs[i]),
              ),
            ),
    );
  }

  Widget _buildPdfCard(PdfFile pdf) {
    final date = '${pdf.createdAt.day.toString().padLeft(2,'0')}/'
                 '${pdf.createdAt.month.toString().padLeft(2,'0')}/'
                 '${pdf.createdAt.year}';
    final time = '${pdf.createdAt.hour.toString().padLeft(2,'0')}:'
                 '${pdf.createdAt.minute.toString().padLeft(2,'0')}';

    // Détecter si c'est un rapport global ou par canalisation
    final isGlobal = pdf.name.contains('Rapport_') &&
      !pdf.name.contains('canal');
    final color = isGlobal
      ? const Color(0xFF8B5CF6)
      : const Color(0xFF22D3EE);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(Icons.picture_as_pdf,
            color: color, size: 24)),
        title: Text(pdf.name,
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 13),
          overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Icon(Icons.calendar_today_outlined,
            color: Colors.grey[600], size: 11),
          const SizedBox(width: 4),
          Text('$date à $time',
            style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          const SizedBox(width: 10),
          Icon(Icons.storage_outlined,
            color: Colors.grey[700], size: 11),
          const SizedBox(width: 4),
          Text(PdfStorageService.formatSize(pdf.size),
            style: TextStyle(color: Colors.grey[700], fontSize: 11)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Ouvrir
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              path: pdf.path, title: pdf.name))),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.open_in_new,
                color: color, size: 16))),
          const SizedBox(width: 8),
          // Supprimer
          GestureDetector(
            onTap: () => _deletePdf(pdf),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.delete_outline,
                color: Colors.red[400], size: 16))),
        ]),
        onTap: () => _storage.openPdf(pdf.path),
      ),
    );
  }
}