// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:appwrite/models.dart' as models;
import '../services/bzvision_service.dart';

class BzVisionCameraScreen extends StatefulWidget {
  // Optionnels : quand la caméra est ouverte depuis une canalisation
  // (comme pour une inspection), la vidéo enregistrée est rattachée à
  // ce chantier/cette canalisation via BzVisionService. Si absents
  // (ex. bouton caméra global du chantier), la vidéo est quand même
  // sauvegardée galerie + Appwrite, juste sans lien vers une
  // canalisation précise.
  final models.Document? chantierDoc;
  final models.Document? canalisationDoc;
  final String userId;
  final String userName;

  const BzVisionCameraScreen({
    super.key,
    this.chantierDoc,
    this.canalisationDoc,
    this.userId = '',
    this.userName = '',
  });
  @override
  State<BzVisionCameraScreen> createState() => _BzVisionCameraScreenState();
}

class _BzVisionCameraScreenState extends State<BzVisionCameraScreen> {
  final _ipCtrl   = TextEditingController(text: 'http://192.168.5.12:5002');
  bool  _connected = false;
  bool  _connecting = false;
  String? _piBase;
  String? _error;

  bool _recording = false;
  bool _busy = false; // start/stop en cours, désactive le bouton le temps de la requête

  final _service = BzVisionService();

  // Présets d'URL du serveur caméra Pi (pi_camera_server.py, port 5002)
  final _presets = [
    {'label': 'Pi caméra (réseau)',  'url': 'http://192.168.5.12:5002'},
    {'label': 'Pi caméra (hotspot)', 'url': 'http://10.42.0.1:5002'},
    {'label': 'Pi caméra :5002',     'url': 'http://192.168.1.100:5002'},
  ];

  // "Connexion" = vérification que la Pi caméra répond sur /health,
  // pas un vrai flux persistant (l'API est ponctuelle : start/stop/latest).
  Future<void> _connect(String url) async {
    setState(() { _connecting = true; _error = null; });
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
      // Ne perd pas la vidéo en cours : on arrête/finalise avant de
      // quitter l'écran de connexion plutôt que d'abandonner le fichier
      // en enregistrement côté Pi.
      _stopAndSave();
    }
    setState(() { _connected = false; _piBase = null; });
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
          Container(width: 8, height: 8,
            decoration: BoxDecoration(
              color: _connected ? Colors.green : Colors.red,
              shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_connected ? 'CONNECTÉ' : 'BZVISION — CAMÉRA LIVE',
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
        ]),
        actions: [
          if (_connected)
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
      // Pas de vrai flux vidéo live ici : l'API de la Pi (pi_camera_server.py)
      // est start/stop/latest, pas un flux continu. On affiche donc le statut
      // d'enregistrement plutôt qu'une image live.
      Container(
        color: Colors.black,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_recording ? Icons.fiber_manual_record : Icons.videocam,
              color: _recording ? Colors.red : Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(_recording ? 'Enregistrement en cours' : 'Prêt à enregistrer',
              style: TextStyle(color: Colors.grey[400],
                fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_piBase ?? '', style: TextStyle(color: Colors.grey[800],
              fontSize: 10), textAlign: TextAlign.center),
            if (widget.canalisationDoc != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
                child: Text(
                  '📍 ${widget.canalisationDoc!.data['nom'] as String? ?? 'Canalisation'}',
                  style: const TextStyle(color: Color(0xFF22D3EE), fontSize: 11,
                    fontWeight: FontWeight.w700))),
            ],
            const SizedBox(height: 24),
            if (_recording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                  SizedBox(width: 6),
                  Text('REC', style: TextStyle(color: Colors.red,
                    fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
                ])),
          ]),
        ),
      ),
      // Contrôles bas de page
      Positioned(bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black, Colors.transparent])),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _recordBtn(),
          ]),
        )),
    ]);
  }

  // Gros bouton start/stop central, désactivé pendant la requête réseau
  // (_busy) pour éviter un double-tap qui enverrait deux start/stop.
  Widget _recordBtn() {
    final color = _recording ? Colors.red : const Color(0xFF22D3EE);
    return GestureDetector(
      onTap: _busy ? null : (_recording ? _stopAndSave : _startRecording),
      child: Column(children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.4), width: 2)),
          child: _busy
            ? Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: color)))
            : Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                color: color, size: 32)),
        const SizedBox(height: 6),
        Text(_recording ? 'Arrêter' : 'Démarrer',
          style: TextStyle(color: color.withOpacity(0.9),
            fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<void> _startRecording() async {
    if (_piBase == null) return;
    setState(() => _busy = true);
    try {
      final resp = await http
          .post(Uri.parse('$_piBase/video/start'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() { _recording = true; _busy = false; });
      } else {
        setState(() => _busy = false);
        _showSnack('Échec démarrage (${resp.statusCode})', Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('Erreur de connexion à la caméra', Colors.red);
    }
  }

  // Arrête l'enregistrement côté Pi, récupère le fichier fini, le
  // sauvegarde dans la galerie du téléphone, ET l'upload vers Appwrite
  // (comme les autres vidéos BzVision) — en la rattachant à la
  // canalisation si l'écran a été ouvert depuis une canalisation.
  Future<void> _stopAndSave() async {
    if (_piBase == null) return;
    setState(() => _busy = true);
    try {
      final stopResp = await http
          .post(Uri.parse('$_piBase/video/stop'))
          .timeout(const Duration(seconds: 5));
      if (stopResp.statusCode != 200) {
        if (mounted) {
          setState(() { _busy = false; _recording = false; });
          _showSnack('Échec arrêt (${stopResp.statusCode})', Colors.red);
        }
        return;
      }

      final latestResp = await http
          .get(Uri.parse('$_piBase/video/latest'))
          .timeout(const Duration(seconds: 30));
      if (latestResp.statusCode != 200) {
        if (mounted) {
          setState(() { _busy = false; _recording = false; });
          _showSnack('Vidéo indisponible (${latestResp.statusCode})', Colors.red);
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filename = 'bzvision_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(latestResp.bodyBytes);

      // 1. Galerie du téléphone (best-effort — un échec ne bloque pas l'upload app)
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) await Gal.requestAccess(toAlbum: true);
        await Gal.putVideo(file.path, album: 'BzVision');
      } catch (e) {
        print("Erreur sauvegarde galerie : $e");
      }

      // 2. Appwrite Storage (l'app), puis liaison à la canalisation si connue
      final uploaded = await _service.uploadVideo(
        localPath: file.path, filename: filename);
      if (uploaded != null &&
          widget.canalisationDoc != null && widget.chantierDoc != null) {
        await _service.createVideoRecord(
          canalisationId: widget.canalisationDoc!.$id,
          chantierId: widget.chantierDoc!.$id,
          fileId: uploaded.$id,
          filename: filename,
          date: DateTime.now().toIso8601String().substring(0, 10),
          userId: widget.userId,
        );
      }

      if (mounted) {
        setState(() { _busy = false; _recording = false; });
        _showSnack(
          uploaded != null
            ? '✅ Vidéo enregistrée (galerie + BzVision)'
            : '✅ Vidéo enregistrée dans la galerie (échec upload app)',
          Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _busy = false; _recording = false; });
        _showSnack('Erreur pendant la finalisation : $e', Colors.red);
      }
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _buildConnect() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        // Icône
        Center(child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
          child: const Icon(Icons.videocam_outlined,
            color: Color(0xFF22D3EE), size: 36))),
        const SizedBox(height: 20),
        const Center(child: Text('Connexion caméra Wi-Fi',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 18))),
        Center(child: Text('Raspberry Pi • Enregistrement à distance',
          style: TextStyle(color: Colors.grey[600], fontSize: 12))),

        const SizedBox(height: 32),

        // URL manuelle
        Text('ADRESSE DE LA PI CAMÉRA', style: TextStyle(color: Colors.grey[400], fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        TextField(
          controller: _ipCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13,
            fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'http://192.168.5.12:5002',
            hintStyle: TextStyle(color: Colors.grey[700], fontSize: 11),
            prefixIcon: const Icon(Icons.link, color: Color(0xFF22D3EE), size: 18),
            filled: true, fillColor: const Color(0xFF0A0A0F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: _connecting ? null : () => _connect(_ipCtrl.text.trim()),
            icon: _connecting
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.wifi, size: 20),
            label: Text(_connecting ? 'Connexion...' : 'SE CONNECTER',
              style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 13, letterSpacing: 1.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE), foregroundColor: Colors.black,
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

        // Présets rapides
        Text('ACCÈS RAPIDE', style: TextStyle(color: Colors.grey[400], fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        ..._presets.map((p) =>
          GestureDetector(
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
                const Icon(Icons.play_circle_outline,
                  color: Color(0xFF22D3EE), size: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['label']!, style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(p['url']!, style: TextStyle(color: Colors.grey[700],
                    fontSize: 10, fontFamily: 'monospace')),
                ]),
              ]),
            ),
          )
        ),

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
            Expanded(child: Text(
              'Assurez-vous que votre téléphone et le Raspberry Pi sont connectés au même réseau Wi-Fi. '
              'L\'enregistrement se fait par périodes (démarrer / arrêter), pas en flux continu.',
              style: TextStyle(color: Colors.orange[200], fontSize: 11, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
