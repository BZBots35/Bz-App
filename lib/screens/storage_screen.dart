// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/lang_service.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  static const double _maxBytes = 2 * 1024 * 1024 * 1024;

  final _lang = LangService();
  bool _loading = true;

  int _videosSize   = 0;
  int _pdfsSize     = 0;
  int _capturesSize = 0;
  int _reportsSize  = 0;

  List<FileSystemEntity> _videos   = [];
  List<FileSystemEntity> _pdfs     = [];
  List<FileSystemEntity> _captures = [];
  List<FileSystemEntity> _reports  = [];

  String? _basePath;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    setState(() => _loading = true);
    try {
      final dir  = await getApplicationDocumentsDirectory();
      _basePath  = dir.path;

      final dirs = {
        'videos'  : 'bzbots_videos',
        'captures': 'bzbots_captures',
        'pdfs'    : 'bzbots_pdfs',
        'reports' : 'bzbots_reports',
      };

      int videosSize = 0, pdfsSize = 0, capturesSize = 0, reportsSize = 0;
      List<FileSystemEntity> videos = [], pdfs = [], captures = [], reports = [];

      for (final entry in dirs.entries) {
        final folder = Directory('${dir.path}/${entry.value}');
        if (!await folder.exists()) continue;
        final files = folder.listSync().whereType<File>().toList()
          ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
        int size = 0;
        for (final f in files) size += f.statSync().size;
        switch (entry.key) {
          case 'videos'  : videos   = files; videosSize   = size; break;
          case 'captures': captures = files; capturesSize = size; break;
          case 'pdfs'    : pdfs     = files; pdfsSize     = size; break;
          case 'reports' : reports  = files; reportsSize  = size; break;
        }
      }

      if (mounted) setState(() {
        _videos       = videos;
        _captures     = captures;
        _pdfs         = pdfs;
        _reports      = reports;
        _videosSize   = videosSize;
        _capturesSize = capturesSize;
        _pdfsSize     = pdfsSize;
        _reportsSize  = reportsSize;
        _loading      = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalSize => _videosSize + _pdfsSize + _capturesSize + _reportsSize;
  double get _usageRatio => (_totalSize / _maxBytes).clamp(0.0, 1.0);

  String _formatSize(int bytes) {
    if (bytes < 1024)               return '$bytes o';
    if (bytes < 1024 * 1024)        return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Go';
  }

  Color get _usageColor {
    if (_usageRatio < 0.6)  return Colors.green;
    if (_usageRatio < 0.85) return const Color(0xFFEAB308);
    return Colors.red;
  }

  Future<void> _deleteFile(FileSystemEntity file) async {
    final fileName = file.path.split('/').last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Text(_lang.t('deleteFileTitle'),
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
          '${_lang.t('deleteFileConfirm').replaceAll('?', '')} "$fileName" ?',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_lang.t('cancelBtn'),
              style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white),
            child: Text(_lang.t('delete'),
              style: const TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (confirm == true) {
      await file.delete();
      _loadStorage();
    }
  }

  Future<void> _clearCategory(
      List<FileSystemEntity> files, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Text('${_lang.t('clearCategoryTitle')}$label',
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(_lang.t('clearCategoryConfirm'),
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_lang.t('cancelBtn'),
              style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white),
            child: Text(_lang.t('deleteAllBtn'),
              style: const TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (confirm == true) {
      for (final f in files) await f.delete();
      _loadStorage();
    }
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
        title: Text(_lang.t('storageTitle'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh,
              color: Color(0xFF22D3EE), size: 20),
            onPressed: _loadStorage),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : RefreshIndicator(
            onRefresh: _loadStorage,
            color: const Color(0xFF22D3EE),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStorageBar(),
                const SizedBox(height: 20),
                _buildCategoryRow(),
                const SizedBox(height: 24),
                _buildSection(
                  label : _lang.t('videosLabel'),
                  icon  : Icons.videocam_outlined,
                  color : const Color(0xFF22D3EE),
                  size  : _videosSize,
                  files : _videos,
                  ext   : '.mp4',
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label : _lang.t('capturesLabel'),
                  icon  : Icons.photo_library_outlined,
                  color : const Color(0xFFEAB308),
                  size  : _capturesSize,
                  files : _captures,
                  ext   : '.jpg',
                ),
                const SizedBox(height: 16),
                _buildSection(
                  label : _lang.t('reportsLabel'),
                  icon  : Icons.picture_as_pdf_outlined,
                  color : const Color(0xFFA855F7),
                  size  : _pdfsSize + _reportsSize,
                  files : [..._pdfs, ..._reports],
                  ext   : '.pdf',
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
    );
  }

  Widget _buildStorageBar() {
    final color = _usageColor;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.08), blurRadius: 20)]),
      child: Column(children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3))),
            child: Icon(Icons.storage_outlined, color: color, size: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lang.t('localStorage'),
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 14)),
              Text(_lang.t('storageLimit'),
                style: TextStyle(color: Colors.grey[600], fontSize: 11)),
            ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_formatSize(_totalSize),
              style: TextStyle(color: color,
                fontSize: 18, fontWeight: FontWeight.w900)),
            Text('/ 2,00 Go',
              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _usageRatio,
            minHeight: 10,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(_usageRatio * 100).toStringAsFixed(1)}'
            '${_lang.t('usedSuffix')}',
            style: TextStyle(color: color,
              fontSize: 11, fontWeight: FontWeight.w700)),
          Text('${_formatSize(_maxBytes.toInt() - _totalSize)}'
            '${_lang.t('availableSuffix')}',
            style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        ]),
        if (_usageRatio >= 0.85) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _usageRatio >= 1.0
                  ? _lang.t('storageFull')
                  : _lang.t('storageAlmostFull'),
                style: const TextStyle(color: Colors.red,
                  fontSize: 11, fontWeight: FontWeight.w700))),
            ])),
        ],
      ]),
    );
  }

  Widget _buildCategoryRow() {
    return Row(children: [
      _categoryChip(_lang.t('videosLabel'),   _videosSize,
        const Color(0xFF22D3EE), Icons.videocam_outlined),
      const SizedBox(width: 8),
      _categoryChip(_lang.t('capturesLabel'), _capturesSize,
        const Color(0xFFEAB308), Icons.photo_library_outlined),
      const SizedBox(width: 8),
      _categoryChip(_lang.t('pdfsLabel'),
        _pdfsSize + _reportsSize,
        const Color(0xFFA855F7), Icons.picture_as_pdf_outlined),
    ]);
  }

  Widget _categoryChip(
      String label, int size, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(_formatSize(size),
            style: TextStyle(color: color,
              fontSize: 12, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: Colors.grey[600],
            fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _buildSection({
    required String label,
    required IconData icon,
    required Color color,
    required int size,
    required List<FileSystemEntity> files,
    required String ext,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.grey[300],
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text('${files.length}',
                style: TextStyle(color: color,
                  fontSize: 9, fontWeight: FontWeight.w900))),
            const Spacer(),
            Text(_formatSize(size),
              style: TextStyle(color: color,
                fontSize: 12, fontWeight: FontWeight.w700)),
            if (files.isNotEmpty) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _clearCategory(files, label),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.2))),
                  child: Text(_lang.t('clearBtn'),
                    style: const TextStyle(color: Colors.red,
                      fontSize: 9, fontWeight: FontWeight.w900)))),
            ],
          ]),
        ),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10)),
              child: Text(_lang.t('noFile'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700],
                  fontSize: 11, fontWeight: FontWeight.w700))))
        else
          ...files.take(5).map((f) => _buildFileRow(f, color)),
        if (files.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              '+ ${files.length - 5}${_lang.t('additionalFiles')}',
              style: TextStyle(color: Colors.grey[700], fontSize: 10,
                fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _buildFileRow(FileSystemEntity file, Color color) {
    final name     = file.path.split('/').last;
    final size     = file.statSync().size;
    final modified = file.statSync().modified;
    final dateStr  = '${modified.day.toString().padLeft(2, '0')}/'
                     '${modified.month.toString().padLeft(2, '0')}/'
                     '${modified.year} '
                     '${modified.hour.toString().padLeft(2, '0')}:'
                     '${modified.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.04))),
      child: Row(children: [
        Icon(Icons.insert_drive_file_outlined, color: color, size: 14),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white,
              fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(dateStr,
              style: TextStyle(color: Colors.grey[700], fontSize: 9)),
          ])),
        Text(_formatSize(size),
          style: TextStyle(color: Colors.grey[500],
            fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _deleteFile(file),
          child: Icon(Icons.delete_outline,
            color: Colors.red[700], size: 16)),
      ]),
    );
  }
}