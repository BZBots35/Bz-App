// ignore_for_file: deprecated_member_use
//
// ARCHITECTURE (v5) : la Pi streame la caméra en MJPEG continu
// (/video/live, inchangé). Cet écran :
//   1. Parse le flux MJPEG LUI-MÊME, en octets bruts (recherche des
//      marqueurs JPEG standards SOI/EOI) — approche fiable, validée,
//      ne dépend d'aucun package tiers ni du format exact du boundary.
//   2. Affiche chaque frame reçue en direct (Image.memory).
//   3. Pendant un enregistrement, échantillonne ~1 frame/seconde
//      directement depuis le flux déjà parsé et les écrit dans un
//      dossier temporaire — PLUS besoin de capturer l'écran entier
//      (fini la notification système persistante, le blocage du
//      téléphone pendant l'enregistrement, les boutons visibles dans
//      la vidéo finale).
//   4. À l'arrêt, ffmpeg assemble ces images en vidéo timelapse
//      accélérée (framerate de lecture > cadence d'échantillonnage),
//      puis sauvegarde galerie + Appwrite.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:appwrite/models.dart' as models;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/bzvision_service.dart';

// Facteur d'accélération appliqué à la vidéo temps réel enregistrée
// pour retrouver l'effet timelapse (x10 -> 10 min de direct capturé
// deviennent 1 min de vidéo finale). Ajuster ici seulement.
const int kTimelapseSpeedFactor = 10;

class BzVisionCameraScreen extends StatefulWidget {
  final models.Document? chantierDoc;
  final models.Document? canalisationDoc;
  final String userId;
  final String userName;
  // Optionnel : quand cet écran est ouvert depuis pump_operation_screen
  // pour filmer l'inspection d'une passe précise (canalisation "pompe"
  // à plusieurs passes). Transmis tel quel à createVideoRecord.
  final String? passNum;

  const BzVisionCameraScreen({
    super.key,
    this.chantierDoc,
    this.canalisationDoc,
    this.userId = '',
    this.userName = '',
    this.passNum,
  });
  @override
  State<BzVisionCameraScreen> createState() => _BzVisionCameraScreenState();
}

class _BzVisionCameraScreenState extends State<BzVisionCameraScreen> {
  final _ipCtrl = TextEditingController(text: 'http://192.168.5.12:5002');
  bool _connected = false;
  bool _connecting = false;
  String? _piBase;
  String? _error;

  final _presets = [
    {'label': 'Pi caméra (réseau)', 'url': 'http://192.168.5.12:5002'},
    {'label': 'Pi caméra (hotspot)', 'url': 'http://10.42.0.1:5002'},
  ];

  final _service = BzVisionService();

  // ── Commande vocale (signalement d'anomalie) ──
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _liveTranscript = '';

  // ── Flux MJPEG brut (parsing manuel) ──
  http.Client? _streamClient;
  StreamSubscription<List<int>>? _streamSub;
  final List<int> _streamBuffer = [];
  Uint8List? _currentFrame;
  String? _streamError;
  int _frameCount = 0; // utile pour vérifier que ça reçoit bien qqch

  bool _recording = false;
  bool _starting = false;
  bool _finalizing = false;

  // ── Échantillonnage local pour l'enregistrement (plus de capture
  // d'écran — on écrit directement les frames déjà parsées du flux) ──
  Directory? _sessionDir;
  int _frameIndex = 0;
  DateTime? _lastSampleTime;

  @override
  void dispose() {
    _streamSub?.cancel();
    _streamClient?.close();
    _ipCtrl.dispose();
    if (_isListening) _speech.stop();
    // Best-effort : si l'écran est quitté pendant un enregistrement,
    // on nettoie le dossier de frames échantillonnées sans essayer de
    // les assembler (l'écran n'existe plus pour afficher le résultat).
    _sessionDir?.delete(recursive: true).catchError((_) => Directory(''));
    super.dispose();
  }

  Future<void> _connect(String url) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final resp = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _piBase = base;
          _connected = true;
          _connecting = false;
        });
        await _startLiveStream();
      } else {
        setState(() {
          _error = 'La Pi a répondu avec une erreur (${resp.statusCode})';
          _connecting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Impossible de joindre la Pi à cette adresse. "
            "Vérifie que tu es bien connecté à son réseau/hotspot.";
        _connecting = false;
      });
    }
  }

  void _disconnect() {
    if (_recording) {
      _stopAndSave();
    }
    _streamSub?.cancel();
    _streamSub = null;
    _streamClient?.close();
    _streamClient = null;
    _streamBuffer.clear();
    setState(() {
      _connected = false;
      _piBase = null;
      _currentFrame = null;
      _frameCount = 0;
    });
  }

  // ── Parsing MJPEG brut : recherche des marqueurs JPEG standards
  // SOI (0xFFD8) et EOI (0xFFD9) directement dans le flux d'octets.
  // Robuste par construction : ne dépend d'aucune hypothèse sur le
  // format exact du texte du boundary/des en-têtes HTTP du serveur.
  static const _soi = [0xFF, 0xD8];
  static const _eoi = [0xFF, 0xD9];

  Future<void> _startLiveStream() async {
    if (_piBase == null) return;
    _streamClient = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('$_piBase/video/live'));
      final response = await _streamClient!.send(request);
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _streamError = 'Flux indisponible (${response.statusCode})');
        }
        return;
      }
      _streamBuffer.clear();
      _streamSub = response.stream.listen(
        (chunk) {
          _streamBuffer.addAll(chunk);
          _extractFrames();
        },
        onError: (e) {
          if (mounted) setState(() => _streamError = 'Flux interrompu : $e');
        },
        onDone: () {
          if (mounted) setState(() => _streamError = 'Flux terminé côté Pi');
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) setState(() => _streamError = 'Impossible de démarrer le flux : $e');
    }
  }

  void _extractFrames() {
    while (true) {
      final start = _indexOfBytes(_streamBuffer, _soi, 0);
      if (start == -1) {
        if (_streamBuffer.length > 8192) {
          _streamBuffer.removeRange(0, _streamBuffer.length - 2);
        }
        return;
      }
      if (start > 0) {
        _streamBuffer.removeRange(0, start);
      }
      final end = _indexOfBytes(_streamBuffer, _eoi, 2);
      if (end == -1) {
        return; // image incomplète, attend le prochain chunk
      }
      final frameEnd = end + 2;
      final frame = Uint8List.fromList(_streamBuffer.sublist(0, frameEnd));
      _streamBuffer.removeRange(0, frameEnd);
      _onFrame(frame);
    }
  }

  int _indexOfBytes(List<int> haystack, List<int> needle, int start) {
    final limit = haystack.length - needle.length;
    for (int i = start; i <= limit; i++) {
      if (haystack[i] == needle[0] && haystack[i + 1] == needle[1]) return i;
    }
    return -1;
  }

  void _onFrame(Uint8List frame) {
    if (!mounted) return;
    setState(() {
      _currentFrame = frame;
      _streamError = null;
      _frameCount++;
    });
    if (_recording) _maybeSampleFrame(frame);
  }

  // Échantillonne ~1 frame/seconde vers le dossier de la session en
  // cours — c'est cet écart (échantillon lent, réassemblage à cadence
  // de lecture plus rapide) qui crée l'effet timelapse accéléré.
  Future<void> _maybeSampleFrame(Uint8List frame) async {
    final now = DateTime.now();
    if (_lastSampleTime != null &&
        now.difference(_lastSampleTime!) < const Duration(seconds: 1)) {
      return;
    }
    _lastSampleTime = now;
    final dir = _sessionDir;
    if (dir == null) return;
    final path =
        '${dir.path}/frame_${_frameIndex.toString().padLeft(5, '0')}.jpg';
    _frameIndex++;
    try {
      await File(path).writeAsBytes(frame, flush: false);
    } catch (e) {
      print('[BzVision] Erreur écriture frame échantillonnée : $e');
    }
  }

  // ── Démarrage / arrêt — purement local, aucun appel réseau vers la
  // Pi (le flux tourne déjà, on se contente d'échantillonner) ──

  Future<void> _startRecording() async {
    final tempDir = await getTemporaryDirectory();
    final sessionDir = Directory(
        '${tempDir.path}/bzvision_session_${DateTime.now().millisecondsSinceEpoch}');
    await sessionDir.create(recursive: true);
    setState(() {
      _sessionDir = sessionDir;
      _frameIndex = 0;
      _lastSampleTime = null;
      _recording = true;
    });
  }

  Future<void> _stopAndSave() async {
    final dir = _sessionDir;
    setState(() {
      _recording = false;
      _finalizing = true;
    });

    try {
      if (dir == null) return;
      final frames = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (frames.length < 2) {
        _showSnack("Enregistrement trop court — pas assez d'images", Colors.orange);
        return;
      }

      final outDir = await getTemporaryDirectory();
      final filename = 'bzvision_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final outputPath = '${outDir.path}/$filename';
      final pattern = '${dir.path}/frame_%05d.jpg';

      // -framerate = cadence de LECTURE (pas d'échantillonnage, qui
      // reste ~1 image/s via _maybeSampleFrame) -> effet accéléré.
      final cmd = '-y -framerate $kTimelapseSpeedFactor -i "$pattern" '
          '-c:v libx264 -pix_fmt yuv420p -movflags +faststart "$outputPath"';
      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        print('[ffmpeg] échec assemblage : $logs');
        _showSnack('Échec de l\'assemblage vidéo', Colors.red);
        return;
      }

      final videoFile = File(outputPath);

      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) await Gal.requestAccess(toAlbum: true);
        await Gal.putVideo(videoFile.path, album: 'BzVision');
      } catch (e) {
        print('[BzVision] Erreur sauvegarde galerie : $e');
      }

      final uploaded = await _service.uploadVideo(
          localPath: videoFile.path, filename: filename);
      if (uploaded != null &&
          widget.canalisationDoc != null &&
          widget.chantierDoc != null) {
        await _service.createVideoRecord(
          canalisationId: widget.canalisationDoc!.$id,
          chantierId: widget.chantierDoc!.$id,
          fileId: uploaded.$id,
          filename: filename,
          date: DateTime.now().toIso8601String().substring(0, 10),
          userId: widget.userId,
          passNum: widget.passNum,
        );
      }

      if (mounted) {
        _showSnack(
            uploaded != null
                ? '✅ Vidéo enregistrée (galerie + BzVision)'
                : '✅ Vidéo enregistrée dans la galerie (échec upload app)',
            Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erreur pendant la finalisation : $e', Colors.red);
      }
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
      _sessionDir = null;
      if (mounted) setState(() => _finalizing = false);
    }
  }

  // ── Commande vocale : signalement d'anomalie ──
  // Reconnaissance vocale SUR L'APPAREIL (package speech_to_text, via
  // les moteurs natifs Android/iOS) — fonctionne sans connexion
  // internet sur la plupart des appareils (contrairement à un service
  // cloud de transcription), cohérent avec l'usage terrain sans réseau.
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_liveTranscript.trim().isNotEmpty) {
        _showAnomalyConfirmDialog(_liveTranscript.trim());
      }
      return;
    }

    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onError: (e) => print('[BzVision] Erreur reconnaissance vocale : $e'),
      );
      if (!_speechAvailable) {
        _showSnack("Reconnaissance vocale indisponible sur cet appareil", Colors.red);
        return;
      }
    }

    setState(() { _isListening = true; _liveTranscript = ''; });
    await _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        setState(() => _liveTranscript = result.recognizedWords);
      },
    );
  }

  // Le technicien relit et corrige avant envoi — la reconnaissance
  // vocale n'est jamais parfaite, mieux vaut valider que subir une
  // anomalie mal transcrite dans le dossier du chantier.
  Future<void> _showAnomalyConfirmDialog(String initialText) async {
    final ctrl = TextEditingController(text: initialText);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Signaler une anomalie', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Description de l\'anomalie',
            hintStyle: TextStyle(color: Colors.grey)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22D3EE)),
            child: const Text('Enregistrer', style: TextStyle(color: Colors.black))),
        ],
      ),
    );

    if (confirmed != true || ctrl.text.trim().isEmpty) return;

    if (widget.canalisationDoc == null || widget.chantierDoc == null) {
      _showSnack("Anomalie non liée : aucune canalisation associée à cet écran", Colors.orange);
      return;
    }

    final saved = await _service.createAnomaly(
      canalisationId: widget.canalisationDoc!.$id,
      chantierId: widget.chantierDoc!.$id,
      text: ctrl.text.trim(),
      userId: widget.userId,
    );

    _showSnack(saved != null
      ? '✅ Anomalie enregistrée'
      : '⚠️ Échec de l\'enregistrement (pas de réseau ?)',
      saved != null ? Colors.green : Colors.red);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
        title: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: _connected ? Colors.green : Colors.red,
                  shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_connected ? 'CONNECTÉ' : 'BZVISION — DIRECT',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1)),
          if (widget.passNum != null) ...[
            const SizedBox(width: 8),
            Text('· Passe N°${widget.passNum}',
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
        actions: [
          if (_connected && !_recording)
            TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.red, size: 18),
                label: const Text('Déconnecter',
                    style: TextStyle(color: Colors.red, fontSize: 11))),
        ],
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: _connected ? _buildStream() : _buildConnect(),
    );
  }

  Widget _buildStream() {
    return Stack(children: [
      Positioned.fill(
        child: _currentFrame != null
            ? Image.memory(
                _currentFrame!,
                gaplessPlayback: true,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) {
                  // Décodage de l'image échoué — affiché explicitement
                  // au lieu de rester silencieusement noir, pour qu'on
                  // sache que des frames arrivent mais sont invalides.
                  return Container(
                      color: Colors.black,
                      child: Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.broken_image_outlined, color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text('Frame reçue mais invalide (#$_frameCount)',
                            style: const TextStyle(color: Colors.red, fontSize: 12)),
                        Text('${_currentFrame!.length} octets',
                            style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ])));
                },
              )
            : Container(
                color: Colors.black,
                child: Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const CircularProgressIndicator(color: Color(0xFF22D3EE)),
                    const SizedBox(height: 16),
                    Text(_streamError ?? 'Connexion au flux...',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ]),
                ),
              ),
      ),
      // Compteur de frames — debug temporaire pour diagnostiquer.
      Positioned(
        top: 60,
        right: 16,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8)),
            child: Text('frames: $_frameCount',
                style: const TextStyle(color: Colors.white, fontSize: 10))),
      ),
      Positioned(
        top: 16,
        left: 0,
        right: 0,
        child: Center(
          child: Column(children: [
            if (widget.canalisationDoc != null)
              Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
                  child: Text(
                      '📍 ${widget.canalisationDoc!.data['nom'] as String? ?? 'Canalisation'}',
                      style: const TextStyle(
                          color: Color(0xFF22D3EE), fontSize: 11, fontWeight: FontWeight.w700))),
            if (_recording)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withOpacity(0.3))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                    SizedBox(width: 6),
                    Text('REC',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
                  ])),
            if (_finalizing)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22D3EE))),
                    SizedBox(width: 8),
                    Text('Traitement...',
                        style: TextStyle(
                            color: Color(0xFF22D3EE), fontWeight: FontWeight.w700, fontSize: 11)),
                  ])),
          ]),
        ),
      ),
      Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, Colors.transparent])),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _recordBtn(),
              const SizedBox(width: 36),
              _voiceBtn(),
            ]),
          )),
      // Bandeau "en écoute" + transcription en direct, visible
      // uniquement pendant l'écoute — retour immédiat que la
      // reconnaissance capte bien quelque chose.
      if (_isListening)
        Positioned(
          bottom: 140, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.redAccent.withOpacity(0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.mic, color: Colors.redAccent, size: 16),
                SizedBox(width: 6),
                Text('En écoute...', style: TextStyle(color: Colors.redAccent,
                  fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Text(_liveTranscript.isEmpty ? '…' : _liveTranscript,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ),
    ]);
  }

  Widget _voiceBtn() {
    final color = _isListening ? Colors.redAccent : Colors.amber;
    return GestureDetector(
      onTap: _toggleListening,
      child: Column(children: [
        Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: color.withOpacity(_isListening ? 0.2 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5), width: 2)),
            child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: color, size: 26)),
        const SizedBox(height: 6),
        Text('Anomalie',
            style: TextStyle(color: color.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _recordBtn() {
    final color = _recording ? Colors.red : const Color(0xFF22D3EE);
    final disabled = _starting || _finalizing || _currentFrame == null;
    return GestureDetector(
      onTap: disabled ? null : (_recording ? _stopAndSave : _startRecording),
      child: Column(children: [
        Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: color.withOpacity(disabled ? 0.06 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(disabled ? 0.2 : 0.4), width: 2)),
            child: (_starting || _finalizing)
                ? Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: color)))
                : Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                    color: color.withOpacity(disabled ? 0.4 : 1), size: 32)),
        const SizedBox(height: 6),
        Text(_recording ? 'Arrêter' : 'Démarrer',
            style: TextStyle(color: color.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildConnect() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        Center(
            child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE).withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
                child: const Icon(Icons.videocam_outlined, color: Color(0xFF22D3EE), size: 36))),
        const SizedBox(height: 20),
        const Center(
            child: Text('Connexion caméra Wi-Fi',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
        Center(
            child: Text('Raspberry Pi • Flux direct',
                style: TextStyle(color: Colors.grey[600], fontSize: 12))),
        const SizedBox(height: 32),
        Text('ADRESSE DE LA PI CAMÉRA',
            style: TextStyle(
                color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        TextField(
          controller: _ipCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
              hintText: 'http://192.168.5.12:5002',
              hintStyle: TextStyle(color: Colors.grey[700], fontSize: 11),
              prefixIcon: const Icon(Icons.link, color: Color(0xFF22D3EE), size: 18),
              filled: true,
              fillColor: const Color(0xFF0A0A0F),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _connecting ? null : () => _connect(_ipCtrl.text.trim()),
            icon: _connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.wifi, size: 20),
            label: Text(_connecting ? 'Connexion...' : 'SE CONNECTER',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
        ],
        const SizedBox(height: 32),
        Text('ACCÈS RAPIDE',
            style: TextStyle(
                color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        ..._presets.map((p) => GestureDetector(
              onTap: () {
                _ipCtrl.text = p['url']!;
                _connect(p['url']!);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.07))),
                child: Row(children: [
                  const Icon(Icons.play_circle_outline, color: Color(0xFF22D3EE), size: 18),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['label']!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    Text(p['url']!,
                        style: TextStyle(color: Colors.grey[700], fontSize: 10, fontFamily: 'monospace')),
                  ]),
                ]),
              ),
            )),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 16),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    'Une fois connecté, le direct s\'affiche automatiquement. '
                    'Le bouton central enregistre l\'écran pendant le direct, puis '
                    'accélère la vidéo (effet timelapse) avant de la sauvegarder.',
                    style: TextStyle(color: Colors.orange[200], fontSize: 11, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
