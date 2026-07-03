// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:appwrite/models.dart' as models;
import '../services/bzvision_service.dart';
import '../widgets/tutorial_overlay.dart';
import 'bzvision_3d_screen.dart';
import '../services/app_roles.dart';
import '../widgets/lang_selector.dart';
import 'bzvision_videos_screen.dart';

class BzVisionInspectionScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final models.Document chantierDoc;
  final String userRole, userId, userName;
  const BzVisionInspectionScreen({super.key,
    required this.canalisationDoc, required this.chantierDoc,
    required this.userRole, required this.userId, required this.userName});
  @override
  State<BzVisionInspectionScreen> createState() =>
    _BzVisionInspectionScreenState();
}

class _BzVisionInspectionScreenState extends State<BzVisionInspectionScreen>
    with TickerProviderStateMixin {
  final _service  = BzVisionService();
  final _ipCtrl   = TextEditingController(text: 'http://10.42.0.1:5001/snap');
  final _obsCtrl   = TextEditingController();
  final _distCtrl  = TextEditingController();
  // ── NF EN 13508-2 ─────────────────────────────
  String? _selectedCode;
  String? _selectedCategory;

  // ── Conditions pré-inspection (CCTP §4.4.2) ──
  String _meteo          = 'Soleil';
  String _precipitations = 'Aucune';
  String _nettoyage      = 'Oui';
  String _sousNappe      = 'Non';
  String _emplacement    = 'Sous chaussée';
  final  _tempCtrl       = TextEditingController();
  final  _remarqueCtrl   = TextEditingController();
  // ── Objectifs inspection (obligatoires) ───────
  String _objectifInspection = '';
  String _niveauDetail       = '1';
  final  _attenteCtrl        = TextEditingController();
  // ── Champs NF EN 13508-2 manquants ───────────
  String _regulationDebit  = 'Aucune';   // ADC
  String _etatRemblai      = 'Inconnu';  // Astee vert
  String _etatVoirie       = 'Inconnu';  // Astee vert
  String _entreprisePose   = '';         // Astee bleu
  final  _refVideoCtrl     = TextEditingController(); // ABO
  final  _refPhotosCtrl    = TextEditingController(); // ABN

  List<models.Document> _inspections = [];
  bool _loading      = true;
  bool _cameraActive = false;
  int  _streamKey    = 0; // incrémenter pour forcer reconnexion Mjpeg
  bool _isRecording  = false;

  Timer? _liveTimer;
  int    _liveSeconds = 0;
  Timer? _recTimer;
  int    _recSeconds  = 0;

  final List<Map<String, String>>  _annotations     = [];
  final List<Map<String, dynamic>> _sessionCaptures = [];

  late TabController _tabCtrl;

  // ── GlobalKeys pour le tuto ───────────────────
  final _keyStartBtn  = GlobalKey();
  final _keyRecord    = GlobalKey();
  final _keyCapture   = GlobalKey();
  final _keyAnnotate  = GlobalKey();
  final _keyVideos    = GlobalKey();
  bool _showTutorial  = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadInspections();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final show = await TutorialOverlay.shouldShow('bzvision_inspection');
    if (mounted) setState(() => _showTutorial = show);
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _recTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInspections() async {
    setState(() => _loading = true);
    final list = await _service.getInspections(widget.canalisationDoc.$id);
    if (mounted) setState(() { _inspections = list; _loading = false; });
  }

  Future<void> _startCamera() async {
    // Affiche le formulaire de pré-inspection avant de démarrer
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PreInspectionSheet(
        meteo:              _meteo,
        precipitations:     _precipitations,
        nettoyage:          _nettoyage,
        sousNappe:          _sousNappe,
        emplacement:        _emplacement,
        tempCtrl:           _tempCtrl,
        remarqueCtrl:       _remarqueCtrl,
        objectifInspection: _objectifInspection,
        niveauDetail:       _niveauDetail,
        attenteCtrl:        _attenteCtrl,
        regulationDebit:    _regulationDebit,
        etatRemblai:        _etatRemblai,
        etatVoirie:         _etatVoirie,
        entreprisePose:     _entreprisePose,
        refVideoCtrl:       _refVideoCtrl,
        refPhotosCtrl:      _refPhotosCtrl,
        onChanged: (meteo, precip, nettoyage, nappe, empl) {
          setState(() {
            _meteo          = meteo;
            _precipitations = precip;
            _nettoyage      = nettoyage;
            _sousNappe      = nappe;
            _emplacement    = empl;
          });
        },
        onObjectifChanged: (objectif, niveau) {
          setState(() {
            _objectifInspection = objectif;
            _niveauDetail       = niveau;
          });
        },
        onExtrasChanged: (regDebit, remblai, voirie, epose) {
          setState(() {
            _regulationDebit = regDebit;
            _etatRemblai     = remblai;
            _etatVoirie      = voirie;
            _entreprisePose  = epose;
          });
        },
      ),
    );
    if (confirmed != true) return;
    setState(() { _cameraActive = true; _liveSeconds = 0; });
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _liveSeconds++);
    });
    _service.updateCanalisationStatut(widget.canalisationDoc.$id, 'en_cours');
  }

  void _stopCamera() {
    _liveTimer?.cancel();
    _recTimer?.cancel();
    setState(() {
      _cameraActive = false;
      _isRecording  = false;
      _liveSeconds  = 0;
      _recSeconds   = 0;
    });
  }

  String? _recordingFile;

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      _recTimer?.cancel();
      setState(() { _isRecording = false; _recSeconds = 0; });
      try {
        // Stop immédiat — réponse en < 1s maintenant
        final resp = await http.post(
          Uri.parse('http://10.42.0.1:5001/record/stop'))
          .timeout(const Duration(seconds: 10));
        final data = json.decode(resp.body);
        if (data['ok'] == true) {
          final aviFile = data['avi']  as String? ?? data['file'] as String? ?? '';
          final mp4File = data['file'] as String? ?? '';
          // Reconnexion stream après 2s
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _streamKey++);
          });
          if (data['converting'] == true) {
            // Conversion en arrière-plan — on poll jusqu'à ce qu'elle soit prête
            _showSnack('⏳ Conversion vidéo en cours...', Colors.orange);
            _pollConversionAndDownload(aviFile, mp4File);
          } else if (mp4File.isNotEmpty) {
            await _downloadVideo(mp4File);
          }
        }
      } catch (e) {
        if (mounted) _showSnack('Erreur arrêt: $e', Colors.red);
      }
    } else {
      try {
        final resp = await http.post(
          Uri.parse('http://10.42.0.1:5001/record/start'))
          .timeout(const Duration(seconds: 5));
        final data = json.decode(resp.body);
        if (data['ok'] == true) {
          setState(() { _isRecording = true; _recSeconds = 0; });
          _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _recSeconds++);
          });
        }
      } catch (e) {
        if (mounted) _showSnack('Pi inaccessible: $e', Colors.red);
      }
    }
  }

  /// Poll /convert/status/<avi> toutes les 3s jusqu'à 'ready' puis télécharge.
  Future<void> _pollConversionAndDownload(
      String aviFilename, String mp4Filename) async {
    const maxAttempts = 60; // 3 min max
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final resp = await http.get(
          Uri.parse(
            'http://10.42.0.1:5001/convert/status/$aviFilename'))
          .timeout(const Duration(seconds: 5));
        final data = json.decode(resp.body);
        final status = data['status'] as String? ?? '';
        if (status == 'ready') {
          final file = data['file'] as String? ?? mp4Filename;
          _showSnack('✅ Conversion terminée, téléchargement...', Colors.green);
          await _downloadVideo(file);
          return;
        } else if (status == 'error') {
          // Fallback sur le .avi si conversion échouée
          _showSnack('⚠️ Conversion échouée, récupération .avi', Colors.orange);
          await _downloadVideo(aviFilename);
          return;
        }
        // status == 'converting' → on continue à poller
      } catch (_) {
        // Continue polling si erreur réseau temporaire
      }
    }
    if (mounted) _showSnack('⏱ Timeout conversion, vérifiez les vidéos', Colors.red);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
        style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4)));
  }

  Future<void> _downloadVideo(String filename) async {
    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargement de la vidéo...'),
          behavior: SnackBarBehavior.floating));
      final resp = await http.get(
        Uri.parse('http://10.42.0.1:5001/video/$filename'))
        .timeout(const Duration(minutes: 5));
      if (resp.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final videoDir  = Directory('${directory.path}/bzbots_videos');
        if (!await videoDir.exists()) await videoDir.create(recursive: true);
        final localPath = '${videoDir.path}/$filename';
        await File(localPath).writeAsBytes(resp.bodyBytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Vidéo sauvegardée'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _takeSnapshot() async {
    try {
      final resp = await http.get(
        Uri.parse('http://10.42.0.1:5001/snap'))
        .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        // ── Incrustation CCTP §4.1 ────────────────
        final Uint8List stamped = await _stampImage(
          imageBytes: resp.bodyBytes,
          chantier:   widget.chantierDoc.data['nom'] as String? ?? '',
          troncon:    widget.canalisationDoc.data['nom'] as String? ?? '',
          distance:   _distCtrl.text.trim().isNotEmpty
                        ? '${_distCtrl.text.trim()} m'
                        : '—',
          timeCode:   _formatTime(_liveSeconds),
        );

        final directory  = await getApplicationDocumentsDirectory();
        final captureDir = Directory('${directory.path}/bzbots_captures');
        if (!await captureDir.exists()) {
          await captureDir.create(recursive: true);
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final localPath = '${captureDir.path}/capture_$timestamp.jpg';
        await File(localPath).writeAsBytes(stamped);

        // ── Pop-up annotation immédiat ──────────
        if (!mounted) return;
        final meta = await showDialog<Map<String, String>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _SnapAnnotationDialog(
            imagePath: localPath,
            timeCode:  _formatTime(_liveSeconds),
          ),
        );

        setState(() {
          _sessionCaptures.add({
            'path':      localPath,
            'timestamp': timestamp,
            'time':      _formatTime(_liveSeconds),
            'selected':  true,
            // Métadonnées NF EN 13508-2
            'code':      meta?['code']     ?? '',
            'category':  meta?['category'] ?? '',
            'dist':      meta?['dist']     ?? '',
            'horaire':   meta?['horaire']  ?? '',
            'obs':       meta?['obs']      ?? '',
          });
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur capture: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  /// Incruste les métadonnées CCTP §4.1 sur l'image JPEG brute.
  /// Retourne les bytes PNG (dart:ui encode en PNG nativement).
  Future<Uint8List> _stampImage({
    required Uint8List imageBytes,
    required String chantier,
    required String troncon,
    required String distance,
    required String timeCode,
  }) async {
    // 1. Décode l'image source
    final codec     = await ui.instantiateImageCodec(imageBytes);
    final frame     = await codec.getNextFrame();
    final srcImage  = frame.image;
    final W         = srcImage.width.toDouble();
    final H         = srcImage.height.toDouble();

    // 2. Prépare le canvas
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, W, H));

    // 3. Dessine l'image source
    canvas.drawImage(srcImage, Offset.zero, Paint());

    // 4. Bande noire semi-transparente en bas
    final bandH = H * 0.14;
    canvas.drawRect(
      Rect.fromLTWH(0, H - bandH, W, bandH),
      Paint()..color = const Color(0xCC000000),
    );

    // 5. Helper texte
    void drawText(String text, double x, double y,
        {double fontSize = 12,
        Color color = Colors.white,
        FontWeight weight = FontWeight.normal}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: W - x - 8);
      tp.paint(canvas, Offset(x, y));
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final pad  = W * 0.015;
    final yTop = H - bandH + H * 0.018;
    final fs   = (W * 0.022).clamp(10.0, 18.0);

    // Ligne 1 : chantier + date (à droite)
    drawText('⚙ $chantier', pad, yTop,
        fontSize: fs, color: const Color(0xFF22D3EE),
        weight: FontWeight.bold);
    final dateTp = TextPainter(
      text: TextSpan(
        text: dateStr,
        style: TextStyle(
          color: const Color(0xFFCCCCCC), fontSize: fs * 0.85)),
      textDirection: TextDirection.ltr,
    )..layout();
    dateTp.paint(canvas, Offset(W - dateTp.width - pad, yTop));

    // Ligne 2 : tronçon + distance + timecode
    final y2 = yTop + fs * 1.5;
    drawText('▶ $troncon', pad, y2,
        fontSize: fs * 0.9, color: Colors.white);
    drawText('dist: $distance   t=$timeCode',
        W * 0.55, y2,
        fontSize: fs * 0.85, color: const Color(0xFFAAAAAA));

    // 6. Petit badge "BzVision" coin haut gauche
    final badgeW = W * 0.12;
    final badgeH = H * 0.045;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, badgeW, badgeH),
        const Radius.circular(4)),
      Paint()..color = const Color(0xCC22D3EE),
    );
    drawText('BzVision', pad + 4, pad + badgeH * 0.15,
        fontSize: badgeH * 0.55,
        color: Colors.black,
        weight: FontWeight.bold);

    // 7. Encode en PNG
    final picture   = recorder.endRecording();
    final uiImage   = await picture.toImage(srcImage.width, srcImage.height);
    final byteData  = await uiImage.toByteData(
        format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Codes NF EN 13508-2 ───────────────────────
  // Structure : catégorie → liste de {code, label}
  static const Map<String, List<Map<String, String>>> _nfCodes = {
    'Déformation': [
      {'code': 'DAF', 'label': 'Affaissement de voûte'},
      {'code': 'DAJ', 'label': 'Déformation générale'},
      {'code': 'DAK', 'label': 'Ovalisation'},
      {'code': 'DAM', 'label': 'Poinçonnement'},
    ],
    'Fissure': [
      {'code': 'FAA', 'label': 'Fissure longitudinale'},
      {'code': 'FAB', 'label': 'Fissure transversale'},
      {'code': 'FAC', 'label': 'Fissure en spirale'},
      {'code': 'FAD', 'label': 'Fissures multiples / faïençage'},
      {'code': 'FAE', 'label': 'Fissure longitudinale ouverte'},
      {'code': 'FAF', 'label': 'Fissure transversale ouverte'},
    ],
    'Rupture / Effondrement': [
      {'code': 'BAB', 'label': 'Écrasement partiel'},
      {'code': 'BAC', 'label': 'Effondrement'},
      {'code': 'BAD', 'label': 'Éclatement'},
      {'code': 'BAE', 'label': 'Trou / Perforation'},
    ],
    'Dégradation surface': [
      {'code': 'CAA', 'label': 'Épaufrure légère'},
      {'code': 'CAB', 'label': 'Épaufrure grave'},
      {'code': 'CAC', 'label': 'Armatures apparentes'},
      {'code': 'CAD', 'label': 'Corrosion surface'},
      {'code': 'CAE', 'label': 'Revêtement cloqué / décollé'},
    ],
    'Assemblage / Joint': [
      {'code': 'JAA', 'label': 'Décalage latéral d\'assemblage'},
      {'code': 'JAB', 'label': 'Décalage vertical d\'assemblage'},
      {'code': 'JAC', 'label': 'Déviation angulaire'},
      {'code': 'JAD', 'label': 'Joint apparent / déboîtement'},
      {'code': 'JAE', 'label': 'Joint défectueux'},
    ],
    'Branchement': [
      {'code': 'BAA', 'label': 'Branchement pénétrant'},
      {'code': 'BAF', 'label': 'Raccordement défectueux'},
      {'code': 'BAG', 'label': 'Raccordement incorrect (position)'},
    ],
    'Obstruction': [
      {'code': 'OAA', 'label': 'Dépôt de sédiments'},
      {'code': 'OAB', 'label': 'Obstacle solide'},
      {'code': 'OAC', 'label': 'Racines'},
      {'code': 'OAD', 'label': 'Graisse / encrassement'},
    ],
    'Infiltration / Exfiltration': [
      {'code': 'IAA', 'label': 'Infiltration active'},
      {'code': 'IAB', 'label': 'Marque d\'infiltration'},
      {'code': 'IAC', 'label': 'Exfiltration'},
    ],
    'Géométrie': [
      {'code': 'PAA', 'label': 'Contre-pente / flache'},
      {'code': 'PAB', 'label': 'Changement de pente'},
      {'code': 'PAC', 'label': 'Changement de section'},
      {'code': 'PAD', 'label': 'Coude / changement direction'},
    ],
  };

  // Ouvre le sélecteur de codes NF EN 13508-2
  Future<void> _showCodePicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Nf13508Picker(
        onSelected: (category, code, label) {
          setState(() {
            _selectedCategory = category;
            _selectedCode     = code;
            _obsCtrl.text     = '[$code] $label';
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _addAnnotation() {
    final obs  = _obsCtrl.text.trim();
    final dist = _distCtrl.text.trim();
    if (obs.isEmpty) return;
    setState(() {
      _annotations.add({
        'obs':      obs,
        'dist':     dist.isEmpty ? '—' : dist,
        'time':     _formatTime(_liveSeconds),
        'operator': widget.userName,
        'code':     _selectedCode ?? '',
        'category': _selectedCategory ?? '',
      });
      _selectedCode     = null;
      _selectedCategory = null;
    });
    _obsCtrl.clear();
    _distCtrl.clear();
  }

  Future<void> _saveInspection() async {
    if (_annotations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ajoutez au moins une annotation avant de sauvegarder'),
        behavior: SnackBarBehavior.floating));
      return;
    }
    // Sérialise les conditions pré-inspection
    final conditions = {
      'meteo':           _meteo,
      'precipitations':  _precipitations,
      'temperature':     _tempCtrl.text.trim(),
      'nettoyage':       _nettoyage,
      'sousNappe':       _sousNappe,
      'emplacement':     _emplacement,
      'remarque':        _remarqueCtrl.text.trim(),
      // NF EN 13508-2 obligatoires
      'regulationDebit': _regulationDebit,      // ADC
      'refVideo':        _refVideoCtrl.text.trim(),   // ABO
      'refPhotos':       _refPhotosCtrl.text.trim(),  // ABN
      // Guide Astee réception
      'etatRemblai':     _etatRemblai,
      'etatVoirie':      _etatVoirie,
      // Non-normatif Astee
      'entreprisePose':  _entreprisePose,
    };
    final conditionsJson = '\n__CONDITIONS__${json.encode(conditions)}';

    final obsText = _annotations.map((a) =>
      '[${a['time']} | ${a['dist']}m] ${a['obs']}').join('\n');
    // Sérialise captures avec métadonnées NF EN 13508-2
    final selectedCaptures = _sessionCaptures
      .where((c) => c['selected'] == true)
      .map((c) => {
        'path':     c['path']     ?? '',
        'time':     c['time']     ?? '',
        'code':     c['code']     ?? '',
        'category': c['category'] ?? '',
        'dist':     c['dist']     ?? '',
        'horaire':  c['horaire']  ?? '',
        'obs':      c['obs']      ?? '',
      }).toList();
    final capturesJson = selectedCaptures.isNotEmpty
      ? '\n__CAPTURES__${json.encode(selectedCaptures)}' : '';
    final now = DateTime.now().toIso8601String().substring(0, 10);
    await _service.createInspection(
      canalisationId:     widget.canalisationDoc.$id,
      chantierId:         widget.chantierDoc.$id,
      date:               now,
      operateur:          widget.userName,
      observations:       obsText + capturesJson + conditionsJson,
      userId:             widget.userId,
      objectifInspection: _objectifInspection,
      attentes:           _attenteCtrl.text.trim(),
      niveauDetail:       _niveauDetail,
    );
    await _service.updateCanalisationStatut(
      widget.canalisationDoc.$id, 'inspecte');
    setState(() { _annotations.clear(); _sessionCaptures.clear(); });
    _stopCamera();
    _loadInspections();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inspection sauvegardée ✓'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final c   = widget.canalisationDoc.data;
    final nom = c['nom'] as String? ?? '';
    final dia = c['diametre'] as String? ?? '';
    final lon = c['longueur'] as String? ?? '';

    return Stack(children: [
      Scaffold(
        backgroundColor: const Color(0xFF050505),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.4),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
          title: Text(nom, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 15)),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: const Color(0xFF22D3EE),
            labelColor: const Color(0xFF22D3EE),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(icon: Icon(Icons.videocam, size: 16), text: 'Inspection'),
              Tab(icon: Icon(Icons.assignment, size: 16), text: 'Rapports'),
            ],
          ),
          actions: [
            IconButton(
              key: _keyVideos,
              icon: const Icon(Icons.video_library,
                color: Color(0xFF22D3EE), size: 22),
              tooltip: 'Mes vidéos',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const BzVisionVideosScreen()))),
            IconButton(
              icon: const Icon(Icons.view_in_ar,
                color: Color(0xFF22D3EE), size: 22),
              tooltip: 'Vue 3D',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BzVision3DScreen(
                  canalisationDoc: widget.canalisationDoc,
                  inspections:     _inspections)))),
            IconButton(
              icon: const Icon(Icons.help_outline,
                color: Colors.white54, size: 20),
              tooltip: 'Revoir le tutoriel',
              onPressed: () async {
                await TutorialOverlay.reset('bzvision_inspection');
                if (mounted) setState(() => _showTutorial = true);
              }),
            const LangSelector(), const SizedBox(width: 8),
          ],
        ),
        body: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              border: Border(
                left: const BorderSide(color: Color(0xFF22D3EE), width: 3),
                bottom: BorderSide(color: Colors.white.withOpacity(0.06)))),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.water,
                  color: Color(0xFF22D3EE), size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom, style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 14)),
                Text('Ø $dia • $lon',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ])),
              if (_cameraActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4))),
                  child: const Row(children: [
                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
                    SizedBox(width: 4),
                    Text('EN DIRECT', style: TextStyle(color: Colors.red,
                      fontSize: 9, fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
                  ])),
            ]),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildInspectionTab(),
                _buildRapportsTab(),
              ],
            ),
          ),
        ]),
      ),

      // Tuto overlay
      if (_showTutorial)
        TutorialOverlay(
          tutorialKey: 'bzvision_inspection',
          onComplete: () => setState(() => _showTutorial = false),
          steps: [
            TutorialStep(
              targetKey: _keyStartBtn,
              title: 'Démarrer le flux vidéo',
              description: 'Appuyez sur ce bouton pour connecter la caméra du Raspberry Pi et démarrer l\'inspection en direct.',
              bubblePosition: TutorialBubblePosition.top),
            TutorialStep(
              targetKey: _keyRecord,
              title: 'Enregistrer la vidéo',
              description: 'Ce bouton lance et arrête l\'enregistrement. La vidéo est automatiquement sauvegardée sur votre téléphone.',
              bubblePosition: TutorialBubblePosition.bottom),
            TutorialStep(
              targetKey: _keyCapture,
              title: 'Prendre une capture',
              description: 'Capturez une image depuis le flux live. Elle sera incluse dans votre rapport d\'inspection PDF.',
              bubblePosition: TutorialBubblePosition.bottom),
            TutorialStep(
              targetKey: _keyAnnotate,
              title: 'Ajouter une annotation',
              description: 'Notez vos observations et la distance depuis l\'entrée. Ces données apparaîtront dans le schéma du rapport.',
              bubblePosition: TutorialBubblePosition.bottom),
            TutorialStep(
              targetKey: _keyVideos,
              title: 'Mes vidéos',
              description: 'Retrouvez toutes vos vidéos enregistrées ici pour les revoir à tout moment.',
              bubblePosition: TutorialBubblePosition.bottom),
          ],
        ),
    ]);
  }

  Widget _buildInspectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.2))),
          child: _cameraActive
            ? _buildActivePlayer()
            : _buildStartPrompt()),

        if (_cameraActive) ...[
          const SizedBox(height: 16),
          _buildCapturesPanel(),
        ],

        if (_annotations.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveInspection,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('SAUVEGARDER L\'INSPECTION',
                style: TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 12, letterSpacing: 1.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildStartPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.3))),
          child: const Icon(Icons.camera_alt,
            color: Color(0xFF22D3EE), size: 28)),
        const SizedBox(height: 12),
        const Text('Prêt pour l\'inspection',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Démarre le flux caméra du Raspberry Pi',
          style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        const SizedBox(height: 16),
        TextField(
          controller: _ipCtrl,
          style: const TextStyle(color: Colors.white,
            fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'http://10.42.0.1:5001/snap',
            hintStyle: TextStyle(color: Colors.grey[700], fontSize: 11),
            prefixIcon: const Icon(Icons.link,
              color: Color(0xFF22D3EE), size: 16),
            filled: true,
            fillColor: Colors.black.withOpacity(0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFF22D3EE).withOpacity(0.3))),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFF22D3EE).withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF22D3EE), width: 1.5))),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _presetBtn('BzVision', 'http://10.42.0.1:5001/snap'),
          const SizedBox(width: 8),
          _presetBtn('Stream', 'http://10.42.0.1:5001/stream'),
          const SizedBox(width: 8),
          _presetBtn('Hotspot', 'http://10.42.0.1:5001/snap'),
        ]),
        const SizedBox(height: 16),
        // Bouton démarrer avec key pour le tuto
        SizedBox(
          key: _keyStartBtn,
          width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: _startCamera,
            icon: const Icon(Icons.play_circle, size: 20),
            label: const Text('DÉMARRER LA VIDÉO',
              style: TextStyle(fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 1.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ]),
    );
  }

  Widget _presetBtn(String label, String url) {
    return GestureDetector(
      onTap: () => setState(() => _ipCtrl.text = url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1))),
        child: Text(label, style: TextStyle(color: Colors.grey[400],
          fontSize: 9, fontWeight: FontWeight.w700))));
  }

  Widget _buildActivePlayer() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withOpacity(0.4))),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
              const SizedBox(width: 4),
              const Text('LIVE', style: TextStyle(color: Colors.red,
                fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ])),
          const SizedBox(width: 10),
          Text(_formatTime(_liveSeconds),
            style: const TextStyle(color: Colors.white,
              fontFamily: 'monospace', fontSize: 12,
              fontWeight: FontWeight.w700)),
          if (_isRecording) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.5))),
              child: Row(children: [
                const Icon(Icons.fiber_manual_record,
                  color: Colors.red, size: 8),
                const SizedBox(width: 4),
                Text('REC ${_formatTime(_recSeconds)}',
                  style: const TextStyle(color: Colors.red,
                    fontSize: 9, fontWeight: FontWeight.w900,
                    fontFamily: 'monospace')),
              ])),
          ],
          const Spacer(),
          // Bouton Terminer
          GestureDetector(
            onTap: _saveInspection,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.5))),
              child: const Row(children: [
                Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 14),
                SizedBox(width: 4),
                Text('Terminer',
                  style: TextStyle(color: Colors.green,
                    fontSize: 10, fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
              ]))),
          const SizedBox(width: 8),
          // Bouton REC avec key
          GestureDetector(
            key: _keyRecord,
            onTap: _toggleRecord,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: (_isRecording ? Colors.red : Colors.white)
                  .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (_isRecording ? Colors.red : Colors.white)
                    .withOpacity(0.3))),
              child: Icon(
                _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                color: _isRecording ? Colors.red : Colors.white,
                size: 16))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _stopCamera,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3))),
              child: const Icon(Icons.stop, color: Colors.orange, size: 16))),
        ]),
      ),
      GestureDetector(
        onTap: () => showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.95),
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(children: [
              SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 8.0,
                  child: Mjpeg(
                    key: ValueKey('fullscreen_$_streamKey'),
                    stream: 'http://10.42.0.1:5001/stream',
                    isLive: true,
                    fit: BoxFit.contain,
                    error: (context, error, stack) => const Center(
                      child: Icon(Icons.signal_wifi_off, color: Colors.red, size: 48)),
                    loading: (context) => const Center(
                      child: CircularProgressIndicator(color: Color(0xFF22D3EE))),
                  ),
                ),
              ),
              Positioned(
                top: 40, right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 20)),
                )),
            ]),
          ),
        ),
        child: ClipRect(
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: SizedBox(
              width: double.infinity,
              child: Mjpeg(
                key: ValueKey(_streamKey),
                stream: 'http://10.42.0.1:5001/stream',
                isLive: true,
                fit: BoxFit.fitWidth,
                error: (context, error, stack) => Container(
                  color: Colors.black,
                  child: Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.signal_wifi_off, color: Colors.red, size: 32),
                    const SizedBox(height: 8),
                    Text('Flux indisponible',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                  ]))),
                loading: (context) => Container(
                  color: Colors.black,
                  child: const Center(child: CircularProgressIndicator(
                    color: Color(0xFF22D3EE), strokeWidth: 2))),
              ),
            ),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
          // Bouton REC
          GestureDetector(
            key: _keyRecord,
            onTap: _toggleRecord,
            child: Column(children: [
              Container(width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _isRecording
                    ? Colors.red.withOpacity(0.25)
                    : Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isRecording
                      ? Colors.red
                      : Colors.white.withOpacity(0.3),
                    width: _isRecording ? 2 : 1)),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: _isRecording ? Colors.red : Colors.white,
                  size: 22)),
              const SizedBox(height: 3),
              Text(_isRecording
                ? 'STOP ${_formatTime(_recSeconds)}'
                : 'REC',
                style: TextStyle(
                  color: _isRecording ? Colors.red : Colors.white70,
                  fontSize: 9, fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
            ])),
          // Bouton capture
          GestureDetector(
            key: _keyCapture,
            onTap: _takeSnapshot,
            child: Column(children: [
              Container(width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE).withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withOpacity(0.4))),
                child: const Icon(Icons.camera_alt,
                  color: Color(0xFF22D3EE), size: 22)),
              const SizedBox(height: 3),
              Text('Capture', style: TextStyle(
                color: const Color(0xFF22D3EE).withOpacity(0.8),
                fontSize: 9, fontWeight: FontWeight.w700)),
            ])),
          _actionBtn(Icons.lightbulb, 'LED +', Colors.amber, () async {
            try {
              await http.post(Uri.parse('http://10.42.0.1:5001/led/plus'))
                .timeout(const Duration(seconds: 3));
            } catch (_) {}
          }),
          _actionBtn(Icons.lightbulb_outline, 'LED -', Colors.amber.withOpacity(0.5), () async {
            try {
              await http.post(Uri.parse('http://10.42.0.1:5001/led/minus'))
                .timeout(const Duration(seconds: 3));
            } catch (_) {}
          }),
        ]),
      ),
    ]);
  }

  Widget _actionBtn(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.2))),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: color.withOpacity(0.6),
          fontSize: 9, fontWeight: FontWeight.w600)),
      ]));
  }

  Widget _buildCapturesPanel() {
    if (_sessionCaptures.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.photo_library_outlined,
              color: Color(0xFF22D3EE), size: 14),
            const SizedBox(width: 8),
            Text(
              'CAPTURES (${_sessionCaptures.length}) — Sélectionnez celles à inclure',
              style: TextStyle(color: Colors.grey[400], fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 1)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: _sessionCaptures.asMap().entries.map((e) {
              final i          = e.key;
              final cap        = e.value;
              final isSelected = cap['selected'] as bool;
              return GestureDetector(
                onTap: () => setState(() =>
                  _sessionCaptures[i]['selected'] = !isSelected),
                child: Stack(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                          ? const Color(0xFF22D3EE)
                          : Colors.grey.withOpacity(0.3),
                        width: isSelected ? 2 : 1)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.file(File(cap['path'] as String),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[900],
                          child: const Icon(Icons.broken_image,
                            color: Colors.grey, size: 24))))),
                  Positioned(bottom: 4, left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4)),
                      child: Text(cap['time'] as String,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 8, fontFamily: 'monospace')))),
                  Positioned(top: 4, right: 4,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: isSelected
                          ? const Color(0xFF22D3EE)
                          : Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1)),
                      child: isSelected
                        ? const Icon(Icons.check,
                            color: Colors.black, size: 12)
                        : null)),
                ]),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildAnnotationPanel() {
    return Container(
      key: _keyAnnotate,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(children: [
        // ── Header ───────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.push_pin_outlined,
              color: Color(0xFF22D3EE), size: 14),
            const SizedBox(width: 8),
            Text('ANNOTATIONS NF EN 13508-2 (${_annotations.length})',
              style: TextStyle(color: Colors.grey[400], fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            // ── Sélecteur de code NF EN 13508-2 ──
            GestureDetector(
              onTap: _showCodePicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedCode != null
                      ? const Color(0xFF22D3EE)
                      : Colors.white.withOpacity(0.08))),
                child: Row(children: [
                  Icon(Icons.code,
                    color: _selectedCode != null
                      ? const Color(0xFF22D3EE)
                      : Colors.grey[700],
                    size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _selectedCode != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22D3EE)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF22D3EE)
                                      .withOpacity(0.5))),
                              child: Text(_selectedCode!,
                                style: const TextStyle(
                                  color: Color(0xFF22D3EE),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace'))),
                            const SizedBox(width: 6),
                            Text(_selectedCategory ?? '',
                              style: TextStyle(
                                color: Colors.grey[500], fontSize: 9)),
                          ]),
                          const SizedBox(height: 2),
                          Text(_obsCtrl.text,
                            style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                        ])
                      : Text('Sélectionner un code NF EN 13508-2...',
                          style: TextStyle(
                            color: Colors.grey[700], fontSize: 12)),
                  ),
                  Icon(Icons.chevron_right,
                    color: Colors.grey[700], size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // ── Observation libre + distance + ajouter ──
            Row(children: [
              Expanded(flex: 3,
                child: TextField(
                  controller: _obsCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Précision / commentaire...',
                    hintStyle: TextStyle(
                      color: Colors.grey[700], fontSize: 11),
                    prefixIcon: const Icon(Icons.notes,
                      color: Color(0xFF22D3EE), size: 16),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08))),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF22D3EE), width: 1.5))),
                )),
              const SizedBox(width: 8),
              Expanded(flex: 1,
                child: TextField(
                  controller: _distCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'm',
                    hintStyle: TextStyle(
                      color: Colors.grey[700], fontSize: 11),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08))),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF22D3EE), width: 1.5))),
                )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addAnnotation,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.add,
                    color: Colors.black, size: 20))),
            ]),
            if (_annotations.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._annotations.asMap().entries.map((e) {
                final i    = e.key;
                final a    = e.value;
                final code = a['code'] as String? ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: code.isNotEmpty
                        ? const Color(0xFF22D3EE).withOpacity(0.25)
                        : const Color(0xFF22D3EE).withOpacity(0.15))),
                  child: Row(children: [
                    Container(width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        shape: BoxShape.circle),
                      child: Center(child: Text('${i + 1}',
                        style: const TextStyle(color: Colors.red,
                          fontSize: 9, fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      if (code.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF22D3EE).withOpacity(0.4))),
                          child: Text(code,
                            style: const TextStyle(
                              color: Color(0xFF22D3EE),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace'))),
                      Text(a['obs']!, style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
                      Row(children: [
                        Text('t=${a['time']}',
                          style: TextStyle(color: Colors.grey[600],
                            fontSize: 9, fontFamily: 'monospace')),
                        const SizedBox(width: 8),
                        Text('${a['dist']}m',
                          style: const TextStyle(
                            color: Color(0xFF22D3EE),
                            fontSize: 9, fontWeight: FontWeight.w700)),
                      ]),
                    ])),
                    GestureDetector(
                      onTap: () => setState(
                        () => _annotations.removeAt(i)),
                      child: Icon(Icons.close,
                        color: Colors.grey[700], size: 14)),
                  ]),
                );
              }),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildRapportsTab() {
    return _loading
      ? const Center(child: CircularProgressIndicator(
          color: Color(0xFF22D3EE)))
      : _inspections.isEmpty
        ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.assignment_outlined,
              color: Colors.grey[700], size: 48),
            const SizedBox(height: 12),
            Text('Aucune inspection enregistrée',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 4),
            Text('Démarrez une inspection dans l\'onglet vidéo',
              style: TextStyle(color: Colors.grey[700], fontSize: 11)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _inspections.length,
            itemBuilder: (_, i) =>
              _buildInspectionCard(_inspections[i], i));
  }

  Widget _buildInspectionCard(models.Document doc, int index) {
    final date      = doc.data['date']         as String? ?? '';
    final operateur = doc.data['operateur']    as String? ?? '';
    final obs       = doc.data['observations'] as String? ?? '';

    final parts = obs.split('__CAPTURES__');
    final obsOnly = parts[0];
    List<String> capturePaths = [];
    if (parts.length > 1) {
      try { capturePaths = List<String>.from(json.decode(parts[1])); }
      catch (_) {}
    }
    final lines = obsOnly.split('\n')
      .where((l) => l.trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.15))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16))),
          child: Row(children: [
            Container(width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.1),
                shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}',
                style: const TextStyle(color: Color(0xFF22D3EE),
                  fontWeight: FontWeight.w900, fontSize: 11)))),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inspection du $date',
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 13)),
              Row(children: [
                Icon(Icons.person_outline,
                  color: Colors.grey[600], size: 11),
                const SizedBox(width: 3),
                Text(operateur, style: TextStyle(
                  color: Colors.grey[600], fontSize: 11)),
                const SizedBox(width: 8),
                Icon(Icons.push_pin_outlined,
                  color: Colors.grey[600], size: 11),
                const SizedBox(width: 3),
                Text(
                  '${lines.length} annotation${lines.length > 1 ? "s" : ""}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                if (capturePaths.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.photo_library_outlined,
                    color: Colors.grey[600], size: 11),
                  const SizedBox(width: 3),
                  Text(
                    '${capturePaths.length} capture${capturePaths.length > 1 ? "s" : ""}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
              ]),
            ])),
            if (widget.userRole == AppRoles.superAdmin ||
                widget.userRole == AppRoles.admin)
              GestureDetector(
                onTap: () async {
                  await _service.deleteInspection(doc.$id);
                  _loadInspections();
                },
                child: Icon(Icons.delete_outline,
                  color: Colors.red[800], size: 16)),
          ]),
        ),
        if (lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: lines.asMap().entries.map((e) {
              final parts2 = e.value.split('] ');
              final meta   = parts2.isNotEmpty
                ? parts2[0].replaceAll('[', '') : '';
              final text   = parts2.length > 1 ? parts2[1] : e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Container(width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      shape: BoxShape.circle),
                    child: Center(child: Text('${e.key + 1}',
                      style: const TextStyle(color: Colors.red,
                        fontSize: 8, fontWeight: FontWeight.w900)))),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(text, style: const TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.4)),
                    if (meta.isNotEmpty)
                      Text(meta, style: TextStyle(
                        color: Colors.grey[600], fontSize: 9,
                        fontFamily: 'monospace')),
                  ])),
                ]),
              );
            }).toList()),
          ),
        if (capturePaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF22D3EE), size: 12),
                const SizedBox(width: 6),
                Text('CAPTURES INCLUSES',
                  style: TextStyle(color: Colors.grey[500], fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: capturePaths.map((path) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(path),
                    width: 60, height: 60, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 60, height: 60,
                      color: Colors.grey[900],
                      child: const Icon(Icons.broken_image,
                        color: Colors.grey, size: 20))))).toList()),
            ]),
          ),
      ]),
    );
  }
}

// ── Sélecteur NF EN 13508-2 ──────────────────────────────────────────────────
class _Nf13508Picker extends StatefulWidget {
  final void Function(String category, String code, String label) onSelected;
  const _Nf13508Picker({required this.onSelected});
  @override
  State<_Nf13508Picker> createState() => _Nf13508PickerState();
}

class _Nf13508PickerState extends State<_Nf13508Picker> {
  String? _expandedCategory;

  static const Map<String, List<Map<String, String>>> _codes =
      _BzVisionInspectionScreenState._nfCodes;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2))),
        // Titre
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.4))),
              child: const Text('NF EN 13508-2',
                style: TextStyle(
                  color: Color(0xFF22D3EE),
                  fontSize: 10, fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'))),
            const SizedBox(width: 10),
            const Text('Codes d\'anomalie',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        // Liste des catégories
        Expanded(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: _codes.entries.map((cat) {
              final isOpen = _expandedCategory == cat.key;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── En-tête catégorie ──
                  GestureDetector(
                    onTap: () => setState(() =>
                      _expandedCategory = isOpen ? null : cat.key),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isOpen
                          ? const Color(0xFF22D3EE).withOpacity(0.08)
                          : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isOpen
                            ? const Color(0xFF22D3EE).withOpacity(0.3)
                            : Colors.white.withOpacity(0.06))),
                      child: Row(children: [
                        Icon(
                          _categoryIcon(cat.key),
                          color: isOpen
                            ? const Color(0xFF22D3EE)
                            : Colors.grey[600],
                          size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(cat.key,
                            style: TextStyle(
                              color: isOpen ? Colors.white : Colors.grey[400],
                              fontWeight: FontWeight.w700, fontSize: 13))),
                        Text('${cat.value.length}',
                          style: TextStyle(
                            color: Colors.grey[700], fontSize: 11)),
                        const SizedBox(width: 6),
                        Icon(
                          isOpen
                            ? Icons.expand_less
                            : Icons.expand_more,
                          color: Colors.grey[600], size: 18),
                      ]),
                    ),
                  ),
                  // ── Codes de la catégorie ──
                  if (isOpen)
                    ...cat.value.map((item) => GestureDetector(
                      onTap: () => widget.onSelected(
                          cat.key, item['code']!, item['label']!),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(24, 2, 12, 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF22D3EE).withOpacity(0.1))),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22D3EE).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF22D3EE)
                                    .withOpacity(0.35))),
                            child: Text(item['code']!,
                              style: const TextStyle(
                                color: Color(0xFF22D3EE),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace'))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item['label']!,
                              style: const TextStyle(
                                color: Colors.white70, fontSize: 12))),
                          const Icon(Icons.add_circle_outline,
                            color: Color(0xFF22D3EE), size: 16),
                        ]),
                      ),
                    )),
                ],
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'Déformation':           return Icons.compress;
      case 'Fissure':               return Icons.linear_scale;
      case 'Rupture / Effondrement':return Icons.warning_amber_outlined;
      case 'Dégradation surface':   return Icons.texture;
      case 'Assemblage / Joint':    return Icons.link_off;
      case 'Branchement':           return Icons.call_split;
      case 'Obstruction':           return Icons.block;
      case 'Infiltration / Exfiltration': return Icons.water_drop_outlined;
      case 'Géométrie':             return Icons.straighten;
      default:                      return Icons.label_outline;
    }
  }
}

// ── Formulaire Pré-Inspection ────────────────────────────────────────────────
class _PreInspectionSheet extends StatefulWidget {
  final String meteo, precipitations, nettoyage, sousNappe, emplacement;
  final String objectifInspection, niveauDetail;
  final String regulationDebit, etatRemblai, etatVoirie, entreprisePose;
  final TextEditingController tempCtrl, remarqueCtrl, attenteCtrl;
  final TextEditingController refVideoCtrl, refPhotosCtrl;
  final void Function(String meteo, String precip,
      String nettoyage, String nappe, String empl) onChanged;
  final void Function(String objectif, String niveau) onObjectifChanged;
  final void Function(String regDebit, String remblai,
      String voirie, String epose) onExtrasChanged;

  const _PreInspectionSheet({
    required this.meteo, required this.precipitations,
    required this.nettoyage, required this.sousNappe,
    required this.emplacement, required this.tempCtrl,
    required this.remarqueCtrl, required this.onChanged,
    required this.objectifInspection, required this.niveauDetail,
    required this.attenteCtrl, required this.onObjectifChanged,
    required this.regulationDebit, required this.etatRemblai,
    required this.etatVoirie, required this.entreprisePose,
    required this.refVideoCtrl, required this.refPhotosCtrl,
    required this.onExtrasChanged,
  });
  @override
  State<_PreInspectionSheet> createState() => _PreInspectionSheetState();
}

class _PreInspectionSheetState extends State<_PreInspectionSheet> {
  late String _meteo, _precip, _nettoyage, _nappe, _empl;
  late String _objectif, _niveau;
  late String _regDebit, _remblai, _voirie, _epose;

  static const _objectifs = [
    '',
    'Contrôle final nouvelle construction (A)',
    'Fin de période de garantie (B)',
    'Inspection de routine (C)',
    'Problème structurel suspecté (D)',
    'Problème opérationnel suspecté (E)',
    'Problème d\'infiltration suspecté (F)',
    'Contrôle final après rénovation (G)',
    'Transfert de propriété (H)',
    'Planification d\'investissement (I)',
    'Étude par échantillon (J)',
    'Inspection préalable réhabilitation (Z1)',
    'Inspection préalable travaux extérieurs (Z2)',
    'Inspection ciblée (Z3)',
    'Autre (Z)',
  ];

  @override
  void initState() {
    super.initState();
    _meteo     = widget.meteo;
    _precip    = widget.precipitations;
    _nettoyage = widget.nettoyage;
    _nappe     = widget.sousNappe;
    _empl      = widget.emplacement;
    _objectif  = widget.objectifInspection;
    _niveau    = widget.niveauDetail;
    _regDebit  = widget.regulationDebit;
    _remblai   = widget.etatRemblai;
    _voirie    = widget.etatVoirie;
    _epose     = widget.entreprisePose;
    widget.attenteCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text.toUpperCase(), style: TextStyle(
      color: Colors.grey[500], fontSize: 9,
      fontWeight: FontWeight.w900, letterSpacing: 2)));

  Widget _chipGroup(List<String> options, String selected,
      void Function(String) onTap) {
    return Wrap(spacing: 8, runSpacing: 8,
      children: options.map((o) {
        final active = o == selected;
        return GestureDetector(
          onTap: () => setState(() => onTap(o)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active
                ? const Color(0xFF22D3EE).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                  ? const Color(0xFF22D3EE)
                  : Colors.white.withOpacity(0.1))),
            child: Text(o, style: TextStyle(
              color: active ? const Color(0xFF22D3EE) : Colors.grey[400],
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal))));
      }).toList());
  }

  Widget _textField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType keyboard = TextInputType.text}) =>
    TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFF22D3EE), size: 16),
        filled: true,
        fillColor: Colors.black.withOpacity(0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))));

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2))),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.4))),
              child: const Text('CCTP §4.4.2',
                style: TextStyle(color: Color(0xFF22D3EE),
                  fontSize: 9, fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'))),
            const SizedBox(width: 10),
            const Text('Conditions d\'intervention',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 15)),
          ])),
        const Divider(color: Colors.white12, height: 1),
        // Formulaire
        Expanded(child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [

            // ═══ SECTION ROUGE — NF EN 13508-2 OBLIGATOIRE ══════════
            _bandeau('NF EN 13508-2 — OBLIGATOIRE', Colors.red),

            // Objectif de l'inspection (ABP)
            _label('🔴 Objet de l\'inspection (ABP) *'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _objectif.isEmpty
                  ? Colors.red.withOpacity(0.6)
                  : const Color(0xFF22D3EE).withOpacity(0.4))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _objectif,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0D0D0D),
                  hint: const Text('Sélectionner *',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  icon: Icon(Icons.expand_more,
                    color: _objectif.isEmpty ? Colors.red
                      : const Color(0xFF22D3EE), size: 18),
                  items: _objectifs.map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o.isEmpty ? '— Choisir —' : o,
                      style: TextStyle(
                        color: o.isEmpty ? Colors.grey[600] : Colors.white70,
                        fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() {
                    _objectif = v ?? '';
                    widget.onObjectifChanged(_objectif, _niveau);
                  })))),
            if (_objectif.isEmpty)
              _erreur('Ce champ est obligatoire'),

            // Attentes spécifiques
            const SizedBox(height: 10),
            _label('🔴 Attentes spécifiques *'),
            _textField(widget.attenteCtrl,
              'Décrivez les anomalies recherchées...', Icons.track_changes_outlined),
            if (widget.attenteCtrl.text.trim().isEmpty)
              _erreur('Ce champ est obligatoire'),

            // Niveau de détail
            const SizedBox(height: 10),
            _label('🔴 Niveau de détail (§1.4 CCTP)'),
            Row(children: [
              _niveauChip('1', 'Niveau 1\nNon quantifié'),
              const SizedBox(width: 10),
              _niveauChip('2', 'Niveau 2\nQuantifié'),
            ]),

            // Référence support vidéo (ABO)
            const SizedBox(height: 10),
            _label('🔴 Référence support vidéo (ABO)'),
            _textField(widget.refVideoCtrl,
              'Ex: VID-001 ou auto-généré', Icons.videocam_outlined),

            // Référence support photos (ABN)
            const SizedBox(height: 10),
            _label('🔴 Référence support photos (ABN)'),
            _textField(widget.refPhotosCtrl,
              'Ex: PHOTOS-001 ou auto-généré', Icons.photo_library_outlined),

            // Régulation du débit (ADC)
            const SizedBox(height: 10),
            _label('🔴 Régulation du débit (ADC)'),
            _chipGroup(
              ['Aucune', 'Limitation', 'Dérivation', 'Obturation',
               'Assèchement'],
              _regDebit, (v) {
                _regDebit = v;
                widget.onExtrasChanged(_regDebit, _remblai, _voirie, _epose);
              }),

            // Météo (ADA)
            const SizedBox(height: 10),
            _label('🔴 Météorologie (ADA)'),
            _chipGroup(
              ['Soleil', 'Nuageux', 'Couvert', 'Pluie', 'Orage'],
              _meteo, (v) {
                _meteo = v;
                widget.onChanged(_meteo, _precip, _nettoyage, _nappe, _empl);
              }),

            // Précipitations (ADA)
            const SizedBox(height: 10),
            _label('🔴 Précipitations (ADA)'),
            _chipGroup(
              ['Aucune', 'Légères', 'Modérées', 'Fortes'],
              _precip, (v) {
                _precip = v;
                widget.onChanged(_meteo, _precip, _nettoyage, _nappe, _empl);
              }),

            // Température (ADB)
            const SizedBox(height: 10),
            _label('🔴 Température extérieure (ADB)'),
            _textField(widget.tempCtrl, 'Ex: 15 °C',
              Icons.thermostat_outlined, keyboard: TextInputType.number),

            // Nettoyage préalable (ACM)
            const SizedBox(height: 10),
            _label('🔴 Nettoyage préalable (ACM)'),
            _chipGroup(
              ['Oui', 'Non', 'Partiel'],
              _nettoyage, (v) {
                _nettoyage = v;
                widget.onChanged(_meteo, _precip, _nettoyage, _nappe, _empl);
              }),

            const SizedBox(height: 20),
            // ═══ SECTION VERTE — GUIDE ASTEE RÉCEPTION ══════════════
            _bandeau('GUIDE ASTEE RÉCEPTION — OBLIGATOIRE', Colors.green),

            // Ouvrage sous nappe
            _label('🟢 Ouvrage sous nappe'),
            _chipGroup(
              ['Non', 'Oui', 'Inconnu'],
              _nappe, (v) {
                _nappe = v;
                widget.onChanged(_meteo, _precip, _nettoyage, _nappe, _empl);
              }),

            // Situation géographique
            const SizedBox(height: 10),
            _label('🟢 Situation géographique (emplacement)'),
            _chipGroup(
              ['Sous chaussée', 'Trottoir', 'Domaine privé',
               'Espaces verts', 'Autre'],
              _empl, (v) {
                _empl = v;
                widget.onChanged(_meteo, _precip, _nettoyage, _nappe, _empl);
              }),

            // État apparent du remblai
            const SizedBox(height: 10),
            _label('🟢 État apparent du remblai'),
            _chipGroup(
              ['Non applicable', 'Bon', 'Moyen', 'Mauvais', 'Inconnu'],
              _remblai, (v) {
                _remblai = v;
                widget.onExtrasChanged(_regDebit, _remblai, _voirie, _epose);
              }),

            // État avancement voirie
            const SizedBox(height: 10),
            _label('🟢 État avancement de la voirie'),
            _chipGroup(
              ['Non applicable', 'Provisoire', 'Définitive', 'Inconnue'],
              _voirie, (v) {
                _voirie = v;
                widget.onExtrasChanged(_regDebit, _remblai, _voirie, _epose);
              }),

            const SizedBox(height: 20),
            // ═══ SECTION BLEUE — NON-NORMATIF ASTEE ════════════════
            _bandeau('NON-NORMATIF ASTEE — OBLIGATOIRE', Colors.blue),

            // Entreprise de pose
            _label('🔵 Entreprise de pose'),
            _textField(widget.remarqueCtrl,
              'Nom de l\'entreprise de pose', Icons.handyman_outlined),

            // Remarque générale
            const SizedBox(height: 10),
            _label('🔵 Remarque générale avant inspection (ADE)'),
            _textField(widget.remarqueCtrl,
              'Observations particulières, niveau eau...',
              Icons.notes),

            const SizedBox(height: 24),
            // ── Bouton Démarrer ──────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: _objectif.isNotEmpty &&
                    widget.attenteCtrl.text.trim().isNotEmpty
                  ? () => Navigator.pop(context, true)
                  : null,
                icon: const Icon(Icons.play_circle_outline, size: 20),
                label: const Text('DÉMARRER L\'INSPECTION',
                  style: TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 13, letterSpacing: 1.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22D3EE),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey[800],
                  disabledForegroundColor: Colors.grey[600],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))))),
            if (_objectif.isEmpty || widget.attenteCtrl.text.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Remplissez l\'objectif et les attentes pour démarrer',
                  style: TextStyle(color: Colors.red[400], fontSize: 11),
                  textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler',
                style: TextStyle(color: Colors.grey, fontSize: 12))),
          ],
        )),
      ]),
    );
  }

  // ── Widgets utilitaires ───────────────────────
  Widget _bandeau(String text, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Row(children: [
      Container(width: 3, height: 14,
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: color,
        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
    ]));

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text, style: TextStyle(
      color: Colors.grey[400], fontSize: 10,
      fontWeight: FontWeight.w700)));

  Widget _erreur(String text) => Padding(
    padding: const EdgeInsets.only(top: 3, left: 4),
    child: Text(text,
      style: TextStyle(color: Colors.red[400], fontSize: 10)));

  Widget _niveauChip(String value, String label) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() {
        _niveau = value;
        widget.onObjectifChanged(_objectif, _niveau);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _niveau == value
            ? const Color(0xFF22D3EE).withOpacity(0.15)
            : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _niveau == value
              ? const Color(0xFF22D3EE)
              : Colors.white.withOpacity(0.08))),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _niveau == value
              ? const Color(0xFF22D3EE) : Colors.grey[500],
            fontSize: 11,
            fontWeight: _niveau == value
              ? FontWeight.w900 : FontWeight.normal,
            height: 1.4)))));
}

// ── Pop-up annotation post-capture ───────────────────────────────────────────
class _SnapAnnotationDialog extends StatefulWidget {
  final String imagePath;
  final String timeCode;
  const _SnapAnnotationDialog({
    required this.imagePath,
    required this.timeCode,
  });
  @override
  State<_SnapAnnotationDialog> createState() => _SnapAnnotationDialogState();
}

class _SnapAnnotationDialogState extends State<_SnapAnnotationDialog> {
  final _distCtrl = TextEditingController();
  final _obsCtrl  = TextEditingController();
  String? _selectedCode;
  String? _selectedCategory;
  String  _horaire = '—';

  static const Map<String, List<Map<String, String>>> _nfCodes = {
    'Déformation': [
      {'code': 'DAF', 'label': 'Affaissement de voûte'},
      {'code': 'DAJ', 'label': 'Déformation générale'},
      {'code': 'DAK', 'label': 'Ovalisation'},
      {'code': 'DAM', 'label': 'Poinçonnement'},
    ],
    'Fissure': [
      {'code': 'FAA', 'label': 'Fissure longitudinale'},
      {'code': 'FAB', 'label': 'Fissure transversale'},
      {'code': 'FAC', 'label': 'Fissure en spirale'},
      {'code': 'FAD', 'label': 'Fissures multiples / faïençage'},
      {'code': 'FAE', 'label': 'Fissure longitudinale ouverte'},
      {'code': 'FAF', 'label': 'Fissure transversale ouverte'},
    ],
    'Rupture / Effondrement': [
      {'code': 'BAB', 'label': 'Écrasement partiel'},
      {'code': 'BAC', 'label': 'Effondrement'},
      {'code': 'BAD', 'label': 'Éclatement'},
      {'code': 'BAE', 'label': 'Trou / Perforation'},
    ],
    'Dégradation surface': [
      {'code': 'CAA', 'label': 'Épaufrure légère'},
      {'code': 'CAB', 'label': 'Épaufrure grave'},
      {'code': 'CAC', 'label': 'Armatures apparentes'},
      {'code': 'CAD', 'label': 'Corrosion surface'},
      {'code': 'CAE', 'label': 'Revêtement cloqué / décollé'},
    ],
    'Assemblage / Joint': [
      {'code': 'JAA', 'label': 'Décalage latéral d\'assemblage'},
      {'code': 'JAB', 'label': 'Décalage vertical d\'assemblage'},
      {'code': 'JAC', 'label': 'Déviation angulaire'},
      {'code': 'JAD', 'label': 'Joint apparent / déboîtement'},
      {'code': 'JAE', 'label': 'Joint défectueux'},
    ],
    'Branchement': [
      {'code': 'BAA', 'label': 'Branchement pénétrant'},
      {'code': 'BAF', 'label': 'Raccordement défectueux'},
      {'code': 'BAG', 'label': 'Raccordement incorrect (position)'},
    ],
    'Obstruction': [
      {'code': 'OAA', 'label': 'Dépôt de sédiments'},
      {'code': 'OAB', 'label': 'Obstacle solide'},
      {'code': 'OAC', 'label': 'Racines'},
      {'code': 'OAD', 'label': 'Graisse / encrassement'},
    ],
    'Infiltration / Exfiltration': [
      {'code': 'IAA', 'label': 'Infiltration active'},
      {'code': 'IAB', 'label': 'Marque d\'infiltration'},
      {'code': 'IAC', 'label': 'Exfiltration'},
    ],
    'Géométrie': [
      {'code': 'PAA', 'label': 'Contre-pente / flache'},
      {'code': 'PAB', 'label': 'Changement de pente'},
      {'code': 'PAC', 'label': 'Changement de section'},
      {'code': 'PAD', 'label': 'Coude / changement direction'},
    ],
  };

  static const List<String> _horaires = [
    '—', '12h', '1h', '2h', '3h', '4h', '5h',
    '6h', '7h', '8h', '9h', '10h', '11h',
  ];

  void _selectCode(String category, String code, String label) {
    setState(() {
      _selectedCategory = category;
      _selectedCode = code;
      if (_obsCtrl.text.isEmpty) _obsCtrl.text = label;
    });
    Navigator.pop(context);
  }

  Future<void> _showCodePicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NfCodePickerSheet(
        codes: _nfCodes,
        onSelected: _selectCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D0D0D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF050505),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF22D3EE).withOpacity(0.4))),
                  child: const Text('NF EN 13508-2',
                    style: TextStyle(color: Color(0xFF22D3EE),
                      fontSize: 9, fontWeight: FontWeight.w900,
                      fontFamily: 'monospace'))),
                const SizedBox(width: 10),
                const Text('Annoter la capture',
                  style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                Text('t=${widget.timeCode}',
                  style: const TextStyle(color: Colors.grey,
                    fontSize: 10, fontFamily: 'monospace')),
              ])),
            // ── Aperçu capture ──
            Container(
              height: 160,
              width: double.infinity,
              color: Colors.black,
              child: Image.file(File(widget.imagePath),
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image,
                    color: Colors.grey, size: 40)))),
            // ── Formulaire ──
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sélecteur code NF
                  GestureDetector(
                    onTap: _showCodePicker,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedCode != null
                            ? const Color(0xFF22D3EE)
                            : Colors.white.withOpacity(0.08))),
                      child: Row(children: [
                        Icon(Icons.code,
                          color: _selectedCode != null
                            ? const Color(0xFF22D3EE) : Colors.grey[700],
                          size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _selectedCode != null
                            ? Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22D3EE).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFF22D3EE).withOpacity(0.5))),
                                child: Text(_selectedCode!,
                                  style: const TextStyle(
                                    color: Color(0xFF22D3EE),
                                    fontSize: 10, fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace'))),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_selectedCategory ?? '',
                                style: TextStyle(
                                  color: Colors.grey[400], fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                            ])
                            : Text('Sélectionner un code (optionnel)',
                              style: TextStyle(
                                color: Colors.grey[700], fontSize: 12))),
                        Icon(Icons.chevron_right,
                          color: Colors.grey[700], size: 18),
                      ]))),
                  const SizedBox(height: 10),
                  // Distance + horaire
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _distCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Distance (m)',
                          hintStyle: TextStyle(
                            color: Colors.grey[700], fontSize: 11),
                          prefixIcon: const Icon(Icons.straighten,
                            color: Color(0xFF22D3EE), size: 16),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.4),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.08))),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.08))),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF22D3EE), width: 1.5))))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _horaire,
                            dropdownColor: const Color(0xFF0D0D0D),
                            style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                            icon: const Icon(Icons.access_time,
                              color: Color(0xFF22D3EE), size: 16),
                            items: _horaires.map((h) =>
                              DropdownMenuItem(
                                value: h,
                                child: Text(
                                  h == '—' ? 'Position horaire' : h,
                                  style: TextStyle(
                                    color: h == '—'
                                      ? Colors.grey[700] : Colors.white,
                                    fontSize: 12)))).toList(),
                            onChanged: (v) =>
                              setState(() => _horaire = v ?? '—'))))),
                  ]),
                  const SizedBox(height: 10),
                  // Commentaire
                  TextField(
                    controller: _obsCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Commentaire / description de l\'anomalie...',
                      hintStyle: TextStyle(
                        color: Colors.grey[700], fontSize: 11),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: Icon(Icons.notes,
                          color: Color(0xFF22D3EE), size: 16)),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.4),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08))),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF22D3EE), width: 1.5)))),
                  const SizedBox(height: 14),
                  // Boutons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: BorderSide(
                            color: Colors.grey.withOpacity(0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: const Text('Passer',
                          style: TextStyle(fontSize: 13)))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, {
                          'code':     _selectedCode     ?? '',
                          'category': _selectedCategory ?? '',
                          'dist':     _distCtrl.text.trim(),
                          'horaire':  _horaire == '—' ? '' : _horaire,
                          'obs':      _obsCtrl.text.trim(),
                        }),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Valider',
                          style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22D3EE),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12)))),
                  ]),
                ])),
          ])));
  }
}

// ── Sélecteur codes NF EN 13508-2 ────────────────────────────────────────────
class _NfCodePickerSheet extends StatefulWidget {
  final Map<String, List<Map<String, String>>> codes;
  final void Function(String category, String code, String label) onSelected;
  const _NfCodePickerSheet({required this.codes, required this.onSelected});
  @override
  State<_NfCodePickerSheet> createState() => _NfCodePickerSheetState();
}

class _NfCodePickerSheetState extends State<_NfCodePickerSheet> {
  String? _expanded;

  IconData _icon(String cat) {
    switch (cat) {
      case 'Déformation':                 return Icons.compress;
      case 'Fissure':                     return Icons.linear_scale;
      case 'Rupture / Effondrement':      return Icons.warning_amber_outlined;
      case 'Dégradation surface':         return Icons.texture;
      case 'Assemblage / Joint':          return Icons.link_off;
      case 'Branchement':                 return Icons.call_split;
      case 'Obstruction':                 return Icons.block;
      case 'Infiltration / Exfiltration': return Icons.water_drop_outlined;
      case 'Géométrie':                   return Icons.straighten;
      default:                            return Icons.label_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.4))),
              child: const Text('NF EN 13508-2',
                style: TextStyle(color: Color(0xFF22D3EE),
                  fontSize: 10, fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'))),
            const SizedBox(width: 10),
            const Text('Codes d\'anomalie',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
          ])),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: widget.codes.entries.map((cat) {
              final isOpen = _expanded == cat.key;
              return Column(children: [
                GestureDetector(
                  onTap: () => setState(() =>
                    _expanded = isOpen ? null : cat.key),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isOpen
                        ? const Color(0xFF22D3EE).withOpacity(0.08)
                        : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isOpen
                          ? const Color(0xFF22D3EE).withOpacity(0.3)
                          : Colors.white.withOpacity(0.06))),
                    child: Row(children: [
                      Icon(_icon(cat.key),
                        color: isOpen
                          ? const Color(0xFF22D3EE) : Colors.grey[600],
                        size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Text(cat.key,
                        style: TextStyle(
                          color: isOpen ? Colors.white : Colors.grey[400],
                          fontWeight: FontWeight.w700, fontSize: 13))),
                      Text('${cat.value.length}',
                        style: TextStyle(
                          color: Colors.grey[700], fontSize: 11)),
                      const SizedBox(width: 6),
                      Icon(isOpen
                        ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey[600], size: 18),
                    ]))),
                if (isOpen)
                  ...cat.value.map((item) => GestureDetector(
                    onTap: () => widget.onSelected(
                      cat.key, item['code']!, item['label']!),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(24, 2, 12, 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF22D3EE).withOpacity(0.1))),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF22D3EE)
                                .withOpacity(0.35))),
                          child: Text(item['code']!,
                            style: const TextStyle(
                              color: Color(0xFF22D3EE),
                              fontSize: 10, fontWeight: FontWeight.w900,
                              fontFamily: 'monospace'))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item['label']!,
                          style: const TextStyle(
                            color: Colors.white70, fontSize: 12))),
                        const Icon(Icons.add_circle_outline,
                          color: Color(0xFF22D3EE), size: 16),
                      ])))),
              ]);
            }).toList())),
      ]));
  }
}