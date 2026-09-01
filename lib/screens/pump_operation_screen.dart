// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:fl_chart/fl_chart.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/pump_service.dart';
import '../services/bzvision_service.dart';
import '../services/lang_service.dart';
import 'pump_control_screen.dart';
import 'bzvision_camera_screen.dart';

class PumpOperationScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final models.Document chantierDoc;
  final double epaisseur;
  final String resinType, userName, userId;

  const PumpOperationScreen({
    super.key,
    required this.canalisationDoc,
    required this.chantierDoc,
    required this.epaisseur,
    required this.resinType,
    required this.userName,
    required this.userId,
  });

  @override
  State<PumpOperationScreen> createState() => _PumpOperationScreenState();
}

class _PumpOperationScreenState extends State<PumpOperationScreen> {
  final _service = PumpService();
  final _bzVisionService = BzVisionService();
  final _lang = LangService();

  // ── Connexion Pi ──────────────────────────────
  static const String _piBase = 'http://10.42.0.1:5000';
  bool _piConnected = false;

  Future<void> _sendCmd(String cmd) async {
    try {
      final resp = await http.post(
        Uri.parse('$_piBase/cmd'),
        headers: {'Content-Type': 'application/json'},
        body: '{"cmd": "$cmd"}',
      ).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        setState(() => _piConnected = true);
      }
    } catch (_) {
      setState(() => _piConnected = false);
    }
  }

  Future<void> _checkPiConnection() async {
    try {
      final resp = await http.get(
        Uri.parse('$_piBase/ping'),
      ).timeout(const Duration(seconds: 2));
      setState(() => _piConnected = resp.statusCode == 200);
    } catch (_) {
      setState(() => _piConnected = false);
    }
  }

  // ── Paramètres de la canalisation ─────────────
  late double _longueur;
  late double _diametre;
  late int _passes;
  late String _label;
  // Épaisseur/passe : par défaut celle du chantier (widget.epaisseur),
  // mais surchargeable par canalisation (champ Appwrite `epaisseur`).
  late double _epaisseurPasse;

  // ── État Passes ───────────────────────────────
  int _passesDone = 0;

  // ── Courbes épaisseur/métrage par passe (clé = numéro de passe) ──
  // Chargées depuis le champ Appwrite `passesData` (JSON), rafraîchies
  // après chaque passe terminée pour pouvoir les reconsulter ici.
  Map<String, dynamic> _passesData = {};
  late models.Document _currentCanalisationDoc;

  // ── Vidéos d'inspection BzVision, par clé de passe ('1','2'... ou
  // 'final' pour l'inspection finale après la dernière passe) ──
  Map<String, models.Document> _passVideoDocs = {};

  double get _qteParPasse =>
      _longueur * (math.pi * _diametre * _epaisseurPasse / 1000);

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _currentCanalisationDoc = widget.canalisationDoc;
    _checkPiConnection();
    final d = widget.canalisationDoc.data;
    _label    = d['label']    as String? ?? '';
    _longueur = double.tryParse(d['longueur'] as String? ?? '10') ?? 10;
    _diametre = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
    _passes   = d['passes']   as int? ?? 4;
    _epaisseurPasse =
        double.tryParse(d['epaisseur'] as String? ?? '') ?? widget.epaisseur;
    _passesDone = d['passesDone'] as int? ?? 0;
    _loadPassesData(d);
    _loadPassVideos();
  }

  Future<void> _loadPassVideos() async {
    final docs = await _bzVisionService
        .getVideosForCanalisation(_currentCanalisationDoc.$id);
    final map = <String, models.Document>{};
    for (final d in docs) {
      final key = d.data['passNum'] as String?;
      if (key != null && key.isNotEmpty) map[key] = d;
    }
    if (mounted) setState(() => _passVideoDocs = map);
  }

  void _loadPassesData(Map<String, dynamic> data) {
    final raw = data['passesData'] as String?;
    if (raw == null || raw.isEmpty) {
      _passesData = {};
      return;
    }
    try {
      _passesData = Map<String, dynamic>.from(json.decode(raw));
    } catch (_) {
      _passesData = {};
    }
  }

  // Recharge la canalisation depuis Appwrite pour récupérer la courbe
  // fraîchement sauvegardée par PumpControlScreen à la fin d'une passe.
  Future<void> _refreshCanalisation() async {
    final fresh = await _service.getCanalisationById(
        widget.chantierDoc.$id, widget.canalisationDoc.$id);
    if (fresh != null && mounted) {
      setState(() {
        _currentCanalisationDoc = fresh;
        _loadPassesData(fresh.data);
      });
    }
  }

  // ── Popup de consultation de la courbe d'une passe ──
  void _showPassCurve(int passNum) {
    final raw = _passesData['$passNum'];
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_lang.t('pumpOpNoCurveRecordedMsg'))));
      return;
    }
    final points = (raw as List)
        .map((p) => FlSpot((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
    if (points.length < 2) return;
    final maxDataY = points.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final maxY = (maxDataY > _epaisseurPasse ? maxDataY : _epaisseurPasse) * 1.2;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFF22D3EE).withOpacity(0.4))),
        title: Row(children: [
          const Icon(Icons.show_chart, color: Color(0xFF22D3EE), size: 20),
          const SizedBox(width: 8),
          Text('${_lang.t('pumpOpCurveTitlePrefix')} N°$passNum',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: points.last.x,
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${v.toStringAsFixed(1).replaceAll('.', ',')}m',
                          style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(1),
                        style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                  ),
                ),
              ),
              borderData: FlBorderData(
                  show: true, border: Border.all(color: Colors.white.withOpacity(0.08))),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: _epaisseurPasse,
                  color: Colors.grey[400]!.withOpacity(0.6),
                  strokeWidth: 1,
                  dashArray: [4, 3],
                  label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: TextStyle(color: Colors.grey[400], fontSize: 8),
                      labelResolver: (line) =>
                          '${_lang.t('pumpChartTargetPrefix')}${_epaisseurPasse.toStringAsFixed(1)}mm'),
                ),
              ]),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: const Color(0xFF22D3EE),
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: const Color(0xFF22D3EE).withOpacity(0.08)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_lang.t('pumpOpCloseBtn'), style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  // ── Inspection avant passe (ou finale) : vidéo BzVision ou
  // confirmation manuelle ──
  // [passKey] vaut '1', '2'... pour une passe précise, ou 'final' pour
  // l'inspection finale faite après la dernière passe.

  Future<void> _recordInspectionVideo(String passKey) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BzVisionCameraScreen(
          chantierDoc: widget.chantierDoc,
          canalisationDoc: _currentCanalisationDoc,
          userId: widget.userId,
          userName: widget.userName,
          passNum: passKey,
        ),
      ),
    );
    // De retour de l'écran BzVision : on recharge pour afficher la
    // vidéo qui vient d'être filmée (si elle a bien été sauvegardée).
    await _loadPassVideos();
  }

  Future<void> _confirmManualInspection(String passKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.red.withOpacity(0.4))),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_lang.t('pumpOpManualInspectionWarningTitle'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13))),
        ]),
        content: Text(_lang.t('pumpOpManualInspectionWarningMsg'),
            style:
                TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_lang.t('pumpOpCancelBtn'),
                  style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(_lang.t('pumpOpManualInspectionConfirmBtn'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_lang.t('pumpOpManualInspectionConfirmedMsg')),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating));
    }
  }

  // ── Modal sécurité avant GO ────────────────────
  Future<void> _showSafetyModal(int passNum) async {
    bool checked = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          backgroundColor: const Color(0xFF0D0D0D),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF22D3EE), width: 1)),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFEAB308), size: 22),
            const SizedBox(width: 8),
            Text('${_lang.t('pumpOpPasseVerificationPrefix')} $passNum — ${_lang.t('pumpOpVerificationSuffix')}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                '${_lang.t('pumpOpBeforeStartingPassPrefix')} $passNum${_lang.t('pumpOpBeforeStartingPassSuffix')}',
                style: TextStyle(
                    color: Colors.grey[400], fontSize: 12, height: 1.5)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setModal(() => checked = !checked),
              child: Row(children: [
                Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        color: checked
                            ? const Color(0xFF22D3EE).withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: checked
                                ? const Color(0xFF22D3EE)
                                : Colors.grey)),
                    child: checked
                        ? const Icon(Icons.check,
                            color: Color(0xFF22D3EE), size: 14)
                        : null),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_lang.t('pumpOpResinReadyCheckLabel'),
                        style: const TextStyle(color: Colors.white, fontSize: 12))),
              ]),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_lang.t('pumpOpCancelBtn'),
                    style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22D3EE),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.withOpacity(0.2)),
              child: Text(_lang.t('pumpOpStartBtn'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      // Naviguer vers le dashboard de contrôle pour cette passe
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PumpControlScreen(
            canalisationDoc: _currentCanalisationDoc,
            chantierDoc:     widget.chantierDoc,
            epaisseur:       _epaisseurPasse,
            resinType:       widget.resinType,
            userName:        widget.userName,
            passNum:         passNum,
            passesDone:      _passesDone,
            longueur:        _longueur,
            diametre:        _diametre,
            passes:          _passes,
            qteParPasse:     _qteParPasse,
            piBase:          _piBase,
          ),
        ),
      );

      // result == true → passe terminée avec succès
      if (result == true && mounted) {
        setState(() => _passesDone++);
        // Récupère la courbe que PumpControlScreen vient de sauvegarder,
        // pour pouvoir la reconsulter tout de suite depuis cet écran.
        await _refreshCanalisation();
        if (_passesDone >= _passes) {
          await _service.updateCanalisation(
            widget.canalisationDoc.$id,
            statut: 'termine',
            passesDone: _passesDone,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('✓ ${_lang.t('pumpOpCanalisationDoneMsg')}'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating));
            Navigator.pop(context);
          }
        } else {
          await _service.updateCanalisation(
            widget.canalisationDoc.$id,
            statut: 'en_cours',
            passesDone: _passesDone,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resinName = widget.resinType == 'spraycoat_plus'
        ? 'Spraycoat+'
        : 'Spraycoat Flex';
    final totalEp = (_epaisseurPasse * _passes).toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('${_lang.t('pumpOpCoatingLabel')} ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
              Text('#${widget.canalisationDoc.data['label'] ?? '—'}',
                  style: const TextStyle(
                      color: Color(0xFF22D3EE),
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _headerBadge('DN${_diametre.toInt()}', const Color(0xFF22D3EE)),
              const SizedBox(width: 6),
              _headerBadge(resinName, Colors.white),
              const SizedBox(width: 6),
              _headerBadge(
                  '${_epaisseurPasse.toStringAsFixed(2)}mm/passe', Colors.white),
            ]),
          ),
        ]),
        actions: [
          Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _piConnected
                      ? const Color(0xFF22D3EE).withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _piConnected
                          ? const Color(0xFF22D3EE).withOpacity(0.3)
                          : Colors.red.withOpacity(0.3))),
              child: Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: _piConnected
                            ? const Color(0xFF22D3EE)
                            : Colors.red,
                        shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_piConnected ? _lang.t('pumpOpPiConnectedLabel') : _lang.t('pumpOpPiOfflineLabel'),
                    style: TextStyle(
                        color: _piConnected
                            ? const Color(0xFF22D3EE)
                            : Colors.red,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ])),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _buildParamsReminder(totalEp, resinName),
          const SizedBox(height: 14),
          _buildPassesList(),
          _buildInspectionVideoSection(),
          _buildFinalInspectionSection(),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // Vidéo affichée : celle de la passe "courante" — la prochaine à
  // faire (ou la dernière si tout est terminé) — pour retrouver tout
  // de suite ce qui vient d'être filmé, sans avoir à naviguer ailleurs.
  Widget _buildInspectionVideoSection() {
    final displayPassNum = (_passesDone + 1).clamp(1, _passes);
    final videoDoc = _passVideoDocs['$displayPassNum'];
    if (videoDoc == null) return const SizedBox.shrink();

    final fileId = videoDoc.data['fileId'] as String?;
    if (fileId == null) return const SizedBox.shrink();
    final url = _bzVisionService.getVideoStreamUrl(fileId);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.videocam, color: Color(0xFF22D3EE), size: 13),
            const SizedBox(width: 6),
            Text(
                '${_lang.t('pumpOpInspectionVideoTitle')} — '
                '${_lang.t('pumpOpPasseLabel')} N°$displayPassNum',
                style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _InspectionVideoPlayer(key: ValueKey(fileId), url: url)),
        ]),
      ),
    );
  }

  // Inspection finale : une fois toutes les passes terminées, on
  // propose à nouveau les 2 boutons (vidéo BzVision / déjà inspecté)
  // pour un dernier contrôle qualité de la canalisation finie — clé
  // 'final', distincte des passes numérotées.
  Widget _buildFinalInspectionSection() {
    if (_passesDone < _passes) return const SizedBox.shrink();
    final videoDoc = _passVideoDocs['final'];
    final fileId = videoDoc?.data['fileId'] as String?;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fact_check_outlined, color: Colors.green, size: 13),
            const SizedBox(width: 6),
            Text(_lang.t('pumpOpFinalInspectionTitle'),
                style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 10),
          _buildInspectionButtonsRow('final'),
          if (fileId != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _InspectionVideoPlayer(
                    key: ValueKey('final_$fileId'),
                    url: _bzVisionService.getVideoStreamUrl(fileId))),
          ],
        ]),
      ),
    );
  }

  Widget _headerBadge(String text, Color color) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 8, fontWeight: FontWeight.w900)));
  }

  Widget _buildParamsReminder(String totalEp, String resinName) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(children: [
        Text(_lang.t('pumpOpParamsReminderTitle'),
            style: TextStyle(
                color: Colors.grey[500],
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(children: [
          _paramCell(_lang.t('pumpOpDiametreLabel'), 'DN${_diametre.toInt()}',
              onTap: _editDiametre),
          _paramCell(_lang.t('pumpOpLongueurLabel'), '${_longueur}m',
              onTap: _editLongueur),
          _paramCell(_lang.t('pumpOpEpPasseLabel'),
              '${_epaisseurPasse.toStringAsFixed(2)}mm',
              onTap: _editEpaisseurPasse),
          _paramCell(_lang.t('pumpOpNbPassesLabel'), '$_passes',
              onTap: _editPasses),
          _paramCell(_lang.t('pumpOpEpTotaleLabel'), '${totalEp}mm'),
          _paramCell(_lang.t('pumpOpQtePasseLabel'),  '${_qteParPasse.toStringAsFixed(2)}L',
              color: const Color(0xFF22D3EE)),
        ]),
      ]),
    );
  }

  // [onTap] rend la cellule cliquable pour l'édition (Diamètre, Longueur,
  // Épaisseur/passe, Nb passes) ; les cellules calculées (Épaisseur
  // totale, Qté/passe) restent en lecture seule (pas de onTap).
  Widget _paramCell(String label, String value,
      {Color color = Colors.white, VoidCallback? onTap}) {
    final valueBox = Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: onTap != null
                ? Border.all(color: color.withOpacity(0.2))
                : null),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.edit, size: 8, color: color.withOpacity(0.6)),
          ],
        ]));

    return Expanded(
        child: Column(children: [
      Text(label,
          style: TextStyle(
              color: Colors.grey[600],
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
          textAlign: TextAlign.center),
      const SizedBox(height: 3),
      onTap != null
          ? GestureDetector(onTap: onTap, child: valueBox)
          : valueBox,
    ]));
  }

  // ── Édition des paramètres depuis "Rappel de paramètres" ──

  Future<void> _editParamDialog({
    required String title,
    required String initialValue,
    required ValueChanged<String> onSave,
    bool decimal = true,
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black.withOpacity(0.4),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_lang.t('pumpOpCancelBtn'),
                  style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black),
            child: Text(_lang.t('pumpOpSaveBtn'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) onSave(result);
  }

  Future<void> _editDiametre() => _editParamDialog(
        title: _lang.t('pumpOpDiametreLabel'),
        initialValue: _diametre.toStringAsFixed(0),
        onSave: (v) async {
          final val = double.tryParse(v);
          if (val == null || val <= 0) return;
          setState(() => _diametre = val);
          await _service.updateCanalisation(_currentCanalisationDoc.$id,
              diametre: v);
        },
      );

  Future<void> _editLongueur() => _editParamDialog(
        title: _lang.t('pumpOpLongueurLabel'),
        initialValue: _longueur.toString(),
        onSave: (v) async {
          final val = double.tryParse(v);
          if (val == null || val <= 0) return;
          setState(() => _longueur = val);
          await _service.updateCanalisation(_currentCanalisationDoc.$id,
              longueur: v);
        },
      );

  Future<void> _editPasses() => _editParamDialog(
        title: _lang.t('pumpOpNbPassesLabel'),
        initialValue: '$_passes',
        decimal: false,
        onSave: (v) async {
          final val = int.tryParse(v);
          if (val == null || val < 1) return;
          setState(() => _passes = val);
          await _service.updateCanalisation(_currentCanalisationDoc.$id,
              passes: val);
        },
      );

  Future<void> _editEpaisseurPasse() => _editParamDialog(
        title: _lang.t('pumpOpEpPasseLabel'),
        initialValue: _epaisseurPasse.toStringAsFixed(2),
        onSave: (v) async {
          final val = double.tryParse(v);
          if (val == null || val <= 0) return;
          setState(() => _epaisseurPasse = val);
          await _service.updateCanalisation(_currentCanalisationDoc.$id,
              epaisseur: v);
        },
      );

  Widget _buildPassesList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.layers, color: Colors.purple, size: 13),
          const SizedBox(width: 6),
          Text(_lang.t('pumpOpInjectionSequenceTitle'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        ...List.generate(_passes, (i) {
          final passNum = i + 1;
          final isDone  = passNum <= _passesDone;
          // Une passe est disponible si c'est la prochaine à faire
          final isNext  = passNum == _passesDone + 1;
          final hasCurve = _passesData.containsKey('$passNum');

          Color borderColor;
          if (isDone)       borderColor = Colors.green.withOpacity(0.4);
          else if (isNext)  borderColor = const Color(0xFF22D3EE).withOpacity(0.4);
          else              borderColor = Colors.white.withOpacity(0.06);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isNext) ...[
                _buildInspectionButtonsRow('$passNum'),
                const SizedBox(height: 6),
              ],
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: isDone
                        ? Colors.green.withOpacity(0.05)
                        : isNext
                            ? const Color(0xFF22D3EE).withOpacity(0.04)
                            : Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor)),
                child: Row(children: [
              Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green.withOpacity(0.2)
                          : isNext
                              ? const Color(0xFF22D3EE).withOpacity(0.15)
                              : Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle),
                  child: Center(
                      child: isDone
                          ? const Icon(Icons.check,
                              color: Colors.green, size: 12)
                          : Text('$passNum',
                              style: TextStyle(
                                  color: isNext
                                      ? const Color(0xFF22D3EE)
                                      : Colors.grey[500],
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${_lang.t('pumpOpPasseLabel')} N°$passNum',
                      style: TextStyle(
                          color: isDone
                              ? Colors.green
                              : isNext
                                  ? Colors.white
                                  : Colors.grey[600],
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
              if (isDone) ...[
                if (hasCurve)
                  GestureDetector(
                    onTap: () => _showPassCurve(passNum),
                    child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF22D3EE).withOpacity(0.4))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.show_chart,
                              color: Color(0xFF22D3EE), size: 12),
                          const SizedBox(width: 3),
                          Text(_lang.t('pumpOpCourbeChipLabel'),
                              style: const TextStyle(
                                  color: Color(0xFF22D3EE),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)),
                        ])),
                  ),
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
              ] else if (isNext)
                GestureDetector(
                    onTap: () => _showSafetyModal(passNum),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.white.withOpacity(0.2),
                                  blurRadius: 6)
                            ]),
                        child: Text(_lang.t('pumpOpGoBtn'),
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w900))))
              else
                // Passes futures verrouillées
                const Icon(Icons.lock_outline,
                    color: Colors.white24, size: 14),
            ]),
              ),
            ],
          );
        }),
      ]),
    );
  }

  Widget _buildInspectionButtonsRow(String passKey) {
    return Row(children: [
      Expanded(
          child: _inspectionActionButton(
        icon: Icons.videocam_outlined,
        label: _lang.t('pumpOpVideoInspectionBtn'),
        color: const Color(0xFF22D3EE),
        onTap: () => _recordInspectionVideo(passKey),
      )),
      const SizedBox(width: 6),
      Expanded(
          child: _inspectionActionButton(
        icon: Icons.handyman_outlined,
        label: _lang.t('pumpOpManualInspectionBtn'),
        color: Colors.orange,
        onTap: () => _confirmManualInspection(passKey),
      )),
    ]);
  }

  Widget _inspectionActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: color, fontSize: 9, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1)),
        ]),
      ),
    );
  }
}
/// Lecteur vidéo intégré pour rejouer une vidéo d'inspection BzVision
/// directement dans pump_operation_screen, sans changer d'écran.
///
/// ⚠️ Nécessite que `MediaKit.ensureInitialized()` ait été appelé une
/// fois au démarrage de l'app (typiquement dans `main()`, avant
/// `runApp`) — media_kit/media_kit_video sont déjà dans le pubspec,
/// mais si aucun autre écran ne les utilise encore, cet appel
/// d'initialisation manque peut-être. Sans lui, la vidéo ne se
/// lira pas (écran noir).
class _InspectionVideoPlayer extends StatefulWidget {
  final String url;

  const _InspectionVideoPlayer({super.key, required this.url});

  @override
  State<_InspectionVideoPlayer> createState() => _InspectionVideoPlayerState();
}

class _InspectionVideoPlayerState extends State<_InspectionVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.url));
  }

  @override
  void didUpdateWidget(covariant _InspectionVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player.open(Media(widget.url));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Video(controller: _controller),
    );
  }
}
