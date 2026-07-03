// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:appwrite/models.dart' as models;
import 'package:gal/gal.dart';                    // pub: gal ^2.3.0
import '../services/bzvision_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTES D'INTÉGRATION
//
// 1. Ajouter dans pubspec.yaml :
//      gal: ^2.3.0
//
// 2. Android — AndroidManifest.xml :
//      <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
//          android:maxSdkVersion="29"/>
//      <!-- Android 10+ : aucune permission nécessaire via MediaStore -->
//
// 3. iOS — Info.plist :
//      <key>NSPhotoLibraryAddUsageDescription</key>
//      <string>BzVision enregistre les vidéos d'inspection dans votre galerie.</string>
//
// 4. Créer le bucket Appwrite "bzvision_videos" dans la console :
//    Permissions → rôle users : create / read / delete
//    File size max : selon besoin (ex. 500 MB)
//    Extensions autorisées : avi, mp4, mkv
// ─────────────────────────────────────────────────────────────────────────────

class BzVisionVideosScreen extends StatefulWidget {
  const BzVisionVideosScreen({super.key});
  @override
  State<BzVisionVideosScreen> createState() => _BzVisionVideosScreenState();
}

class _BzVisionVideosScreenState extends State<BzVisionVideosScreen>
    with SingleTickerProviderStateMixin {
  // ── Onglets ───────────────────────────────────
  late TabController _tab;

  // ── Vidéos locales ────────────────────────────
  List<FileSystemEntity> _localVideos = [];
  bool _loadingLocal = true;

  // ── Vidéos Appwrite Storage ───────────────────
  final _service = BzVisionService();
  List<models.File> _cloudVideos = [];
  bool _loadingCloud = true;

  // ── Téléchargements en cours ──────────────────
  // fileId → progression 0.0–1.0
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadLocalVideos();
    _loadCloudVideos();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Chargement local ──────────────────────────
  Future<void> _loadLocalVideos() async {
    setState(() => _loadingLocal = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${dir.path}/bzbots_videos');
      if (await videoDir.exists()) {
        final files = await videoDir.list().toList();
        final videos = files
            .whereType<File>()
            .where((f) =>
                f.path.endsWith('.avi') ||
                f.path.endsWith('.mp4') ||
                f.path.endsWith('.mkv'))
            .toList();
        videos.sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
        if (mounted) setState(() { _localVideos = videos; _loadingLocal = false; });
      } else {
        if (mounted) setState(() { _localVideos = []; _loadingLocal = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _localVideos = []; _loadingLocal = false; });
    }
  }

  // ── Chargement cloud ──────────────────────────
  Future<void> _loadCloudVideos() async {
    setState(() => _loadingCloud = true);
    final files = await _service.listStorageVideos();
    if (mounted) setState(() { _cloudVideos = files; _loadingCloud = false; });
  }

  // ── Téléchargement vidéo cloud → galerie ──────
  Future<void> _downloadToGallery(models.File cloudFile) async {
    final fileId   = cloudFile.$id;
    final filename = cloudFile.name;

    setState(() => _downloadProgress[fileId] = 0.0);

    try {
      // 1. Récupère les bytes depuis Appwrite
      final Uint8List? bytes = await _service.downloadVideoBytes(
        fileId: fileId,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress[fileId] = received / total);
          }
        },
      );

      if (bytes == null || bytes.isEmpty) throw Exception('Aucune donnée reçue');

      // 2. Écrit dans un fichier temp
      final tmpDir  = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/$filename');
      await tmpFile.writeAsBytes(bytes);

      // 3. Sauvegarde dans la galerie via `gal`
      await Gal.putVideo(tmpFile.path);

      // 4. Nettoie le fichier temp
      await tmpFile.delete();

      if (mounted) {
        setState(() => _downloadProgress.remove(fileId));
        _showSnack('✅ "$filename" enregistrée dans la galerie', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress.remove(fileId));
        _showSnack('❌ Échec du téléchargement : $e', Colors.red);
      }
    }
  }

  // ── Suppression locale ────────────────────────
  Future<void> _deleteLocalVideo(FileSystemEntity file) async {
    final confirm = await _confirmDialog('Supprimer ?',
        'Cette vidéo locale sera supprimée définitivement.');
    if (confirm == true) {
      await file.delete();
      _loadLocalVideos();
    }
  }

  // ── Sauvegarde vidéo locale → galerie ────────
  Future<void> _saveLocalToGallery(File file) async {
    try {
      await Gal.putVideo(file.path);
      _showSnack('✅ "${file.path.split('/').last}" enregistrée dans la galerie',
          Colors.green);
    } catch (e) {
      _showSnack('❌ Échec de l\'enregistrement : $e', Colors.red);
    }
  }

  // ── Suppression cloud ─────────────────────────
  Future<void> _deleteCloudVideo(models.File cloudFile) async {
    final confirm = await _confirmDialog('Supprimer du cloud ?',
        '"${cloudFile.name}" sera supprimée d\'Appwrite Storage.');
    if (confirm == true) {
      final ok = await _service.deleteStorageVideo(cloudFile.$id);
      if (ok) {
        _showSnack('🗑 Vidéo supprimée du cloud', Colors.orange);
        _loadCloudVideos();
      } else {
        _showSnack('❌ Échec de la suppression', Colors.red);
      }
    }
  }

  // ── Helpers UI ────────────────────────────────
  Future<bool?> _confirmDialog(String title, String content) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D0D0D),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(content, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer', style: TextStyle(color: Colors.red))),
          ],
        ),
      );

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  // ── Build principal ───────────────────────────
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
        title: const Text('MES VIDÉOS',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1.5)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              onPressed: () {
                _loadLocalVideos();
                _loadCloudVideos();
              }),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFF22D3EE),
          indicatorWeight: 2,
          labelColor: const Color(0xFF22D3EE),
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android, size: 16), text: 'LOCAL'),
            Tab(icon: Icon(Icons.cloud_outlined, size: 16), text: 'CLOUD'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildLocalTab(),
          _buildCloudTab(),
        ],
      ),
    );
  }

  // ── Onglet LOCAL ──────────────────────────────
  Widget _buildLocalTab() {
    if (_loadingLocal) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22D3EE)));
    }
    if (_localVideos.isEmpty) return _emptyState('Aucune vidéo locale',
        'Enregistrez une inspection pour voir les vidéos ici');

    return RefreshIndicator(
      color: const Color(0xFF22D3EE),
      backgroundColor: const Color(0xFF0A0A0F),
      onRefresh: _loadLocalVideos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _localVideos.length,
        itemBuilder: (_, i) {
          final file = _localVideos[i] as File;
          final name = file.path.split('/').last;
          final stat = file.statSync();
          return _videoCard(
            icon: Icons.phone_android,
            iconColor: const Color(0xFF22D3EE),
            name: name,
            subtitle: _formatDate(stat.modified),
            size: _formatSize(stat.size),
            onPlay: () => _openPlayer(file.path, name),
            onDownload: () => _saveLocalToGallery(file),
            onDelete: () => _deleteLocalVideo(file),
          );
        },
      ),
    );
  }

  // ── Onglet CLOUD ──────────────────────────────
  Widget _buildCloudTab() {
    if (_loadingCloud) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22D3EE)));
    }
    if (_cloudVideos.isEmpty) return _emptyState('Aucune vidéo cloud',
        'Les vidéos uploadées sur Appwrite Storage apparaîtront ici');

    return RefreshIndicator(
      color: const Color(0xFF22D3EE),
      backgroundColor: const Color(0xFF0A0A0F),
      onRefresh: _loadCloudVideos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _cloudVideos.length,
        itemBuilder: (_, i) {
          final f = _cloudVideos[i];
          final isDownloading = _downloadProgress.containsKey(f.$id);
          final progress     = _downloadProgress[f.$id] ?? 0.0;
          final uploadedAt   = DateTime.parse(f.$createdAt);

          return _cloudVideoCard(
            file: f,
            subtitle: _formatDate(uploadedAt),
            size: _formatSize(f.sizeOriginal),
            isDownloading: isDownloading,
            progress: progress,
            onPlay: () {
              final url = _service.getVideoStreamUrl(f.$id);
              _openPlayer(url, f.name);
            },
            onDownload: isDownloading ? null : () => _downloadToGallery(f),
            onDelete: isDownloading ? null : () => _deleteCloudVideo(f),
          );
        },
      ),
    );
  }

  // ── Card vidéo locale ─────────────────────────
  Widget _videoCard({
    required IconData icon,
    required Color iconColor,
    required String name,
    required String subtitle,
    required String size,
    required VoidCallback onPlay,
    required VoidCallback onDownload,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _leadingIcon(icon, iconColor),
        title: Text(name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          Text(size,
              style: TextStyle(color: Colors.grey[700], fontSize: 10)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _iconBtn(Icons.play_arrow, const Color(0xFF22D3EE), onPlay),
          const SizedBox(width: 8),
          _iconBtn(Icons.download_outlined, Colors.greenAccent[400]!, onDownload),
          const SizedBox(width: 8),
          _iconBtn(Icons.delete_outline, Colors.red[400]!, onDelete),
        ]),
      ),
    );
  }

  // ── Card vidéo cloud ──────────────────────────
  Widget _cloudVideoCard({
    required models.File file,
    required String subtitle,
    required String size,
    required bool isDownloading,
    required double progress,
    required VoidCallback onPlay,
    VoidCallback? onDownload,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDownloading
                  ? const Color(0xFF22D3EE).withOpacity(0.6)
                  : const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _leadingIcon(Icons.cloud_done_outlined, Colors.blueAccent),
            title: Text(file.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
                overflow: TextOverflow.ellipsis),
            subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                  Text(size,
                      style: TextStyle(color: Colors.grey[700], fontSize: 10)),
                ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              // Lecture stream
              _iconBtn(Icons.play_arrow, const Color(0xFF22D3EE), onPlay),
              const SizedBox(width: 8),
              // Téléchargement → galerie
              isDownloading
                  ? _progressBtn(progress)
                  : _iconBtn(
                      Icons.download_outlined,
                      Colors.greenAccent[400]!,
                      onDownload ?? () {}),
              const SizedBox(width: 8),
              // Suppression cloud
              _iconBtn(
                  Icons.delete_outline,
                  isDownloading ? Colors.grey : Colors.red[400]!,
                  onDelete ?? () {}),
            ]),
          ),
          // Barre de progression inline pendant le download
          if (isDownloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[900],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF22D3EE)),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Téléchargement… ${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Color(0xFF22D3EE), fontSize: 10),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Widgets utilitaires ───────────────────────
  Widget _leadingIcon(IconData icon, Color color) => Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, color: color, size: 24));

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20)),
      );

  Widget _progressBtn(double progress) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF22D3EE)),
            ),
          ),
          Text(
            '${(progress * 100).toStringAsFixed(0)}',
            style: const TextStyle(
                color: Color(0xFF22D3EE),
                fontSize: 7,
                fontWeight: FontWeight.w700),
          ),
        ]),
      );

  Widget _emptyState(String title, String subtitle) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.videocam_off_outlined, color: Colors.grey[700], size: 56),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      );

  void _openPlayer(String pathOrUrl, String title) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) =>
            _MediaKitPlayerScreen(path: pathOrUrl, title: title)));
  }
}

// ── Lecteur media_kit ─────────────────────────────
class _MediaKitPlayerScreen extends StatefulWidget {
  final String path, title;
  const _MediaKitPlayerScreen({required this.path, required this.title});
  @override
  State<_MediaKitPlayerScreen> createState() => _MediaKitPlayerScreenState();
}

class _MediaKitPlayerScreenState extends State<_MediaKitPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.path));
    _player.stream.error.listen((e) => debugPrint('▶ ERREUR: $e'));
    _player.stream.playing.listen((p) => debugPrint('▶ PLAYING: $p'));
    _player.stream.duration.listen((d) => debugPrint('▶ DURATION: $d'));
    _player.stream.width.listen((w) => debugPrint('▶ WIDTH: $w'));
    _player.stream.height.listen((h) => debugPrint('▶ HEIGHT: $h'));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.width * (3 / 4),
          child: Video(
            controller: _controller,
            controls: NoVideoControls,
            fill: Colors.black,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black,
          child: Column(children: [
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              builder: (_, posSnap) => StreamBuilder<Duration>(
                stream: _player.stream.duration,
                builder: (_, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final progress = dur.inMilliseconds > 0
                      ? pos.inMilliseconds / dur.inMilliseconds
                      : 0.0;
                  return Column(children: [
                    Slider(
                        value: progress.clamp(0.0, 1.0),
                        activeColor: const Color(0xFF22D3EE),
                        inactiveColor: Colors.grey[800],
                        onChanged: (v) => _player.seek(Duration(
                            milliseconds:
                                (v * dur.inMilliseconds).toInt()))),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          Text(_fmt(dur),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ]),
                  ]);
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  icon: const Icon(Icons.replay_10,
                      color: Colors.white, size: 32),
                  onPressed: () async {
                    final pos = _player.state.position;
                    await _player.seek(Duration(
                        seconds: (pos.inSeconds - 10).clamp(0, 99999)));
                  }),
              const SizedBox(width: 16),
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return IconButton(
                      iconSize: 56,
                      icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle,
                          color: const Color(0xFF22D3EE)),
                      onPressed: () => _player.playOrPause());
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                  icon: const Icon(Icons.forward_10,
                      color: Colors.white, size: 32),
                  onPressed: () async {
                    final pos = _player.state.position;
                    final dur = _player.state.duration;
                    await _player.seek(Duration(
                        seconds:
                            (pos.inSeconds + 10).clamp(0, dur.inSeconds)));
                  }),
            ]),
          ]),
        ),
      ]),
    );
  }
}
