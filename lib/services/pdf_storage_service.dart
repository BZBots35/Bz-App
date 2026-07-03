// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class PdfStorageService {
  // ── Dossier de stockage ──────────────────────
  Future<Directory> _getPdfDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/bzbots_rapports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Sauvegarder un PDF ───────────────────────
  Future<String> savePdf(Uint8List bytes, String filename) async {
    final dir  = await _getPdfDir();
    final path = '${dir.path}/$filename.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  // ── Lister tous les PDFs ─────────────────────
  Future<List<PdfFile>> listPdfs({String? chantierPrefix}) async {
    final dir = await _getPdfDir();
    if (!await dir.exists()) return [];
    final files = await dir.list().toList();
    final pdfs  = files
      .whereType<File>()
      .where((f) => f.path.endsWith('.pdf'))
      .where((f) => chantierPrefix == null ||
        f.path.split('/').last.startsWith(chantierPrefix))
      .map((f) {
        final name = f.path.split('/').last.replaceAll('.pdf', '');
        final stat = f.statSync();
        return PdfFile(
          path:      f.path,
          name:      name,
          size:      stat.size,
          createdAt: stat.modified,
        );
      })
      .toList();
    pdfs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pdfs;
  }

  // ── Ouvrir un PDF ────────────────────────────
  Future<void> openPdf(String path) async {
    await OpenFilex.open(path);
  }

  // ── Supprimer un PDF ─────────────────────────
  Future<void> deletePdf(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  // ── Formater la taille ───────────────────────
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

class PdfFile {
  final String path, name;
  final int    size;
  final DateTime createdAt;
  const PdfFile({
    required this.path, required this.name,
    required this.size, required this.createdAt,
  });
}
