// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:printing/printing.dart';
import '../services/pump_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';
import '../services/pdf_storage_service.dart';
import 'pump_rapports_screen.dart';
import 'pump_operation_screen.dart';
import 'pump_pdf_service.dart';

// ── Écran de lecture PDF interne ────────────────
class RapportViewerScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String title;

  const RapportViewerScreen({
    super.key,
    required this.pdfBytes,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: PdfPreview(
        build: (format) => pdfBytes,
        allowSharing: true,
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }
}

class PumpChantierScreen extends StatefulWidget {
  final models.Document chantierDoc;
  final String userId, userName, userRole;
  const PumpChantierScreen({super.key,
    required this.chantierDoc, required this.userId,
    required this.userName, required this.userRole});
  @override
  State<PumpChantierScreen> createState() => _PumpChantierScreenState();
}

class _PumpChantierScreenState extends State<PumpChantierScreen> {
  final _service = PumpService();
  final _lang = LangService();
  List<models.Document> _canalisations = [];
  bool _loading = true;
  bool _addingCanalisation = false;

  // Paramètres globaux
  String _resinType     = 'spraycoat_plus';
  double _epaisseur     = 0.8;
  int    _desiredPasses = 4;

  // Paramètres environnementaux du chantier
  String _tempExt = '';
  String _meteo   = '';
  late TextEditingController _tempExtCtrl;
  late TextEditingController _meteoCtrl;

  // Résines disponibles
  static const _resins = [
    {'id': 'spraycoat_plus', 'label': 'Spraycoat+',
     'epRec': 0.75, 'epMin': 0.5, 'epMax': 0.85},
    {'id': 'spraycoat_flex', 'label': 'Spraycoat Flex',
     'epRec': 1.00, 'epMin': 0.85, 'epMax': 1.15},
  ];

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    final d = widget.chantierDoc.data;
    _resinType     = d['resinType']     as String? ?? 'spraycoat_plus';
    _epaisseur     = double.tryParse(d['epaisseur'] as String? ?? '0.8') ?? 0.8;
    _desiredPasses = d['desiredPasses'] as int? ?? 4;
    
    // Récupération des données environnementales si elles existent dans Appwrite
    _tempExt       = d['tempExt'] as String? ?? '';
    _meteo         = d['meteo'] as String? ?? '';

    _tempExtCtrl   = TextEditingController(text: _tempExt);
    _meteoCtrl     = TextEditingController(text: _meteo);

    _loadCanalisations();
  }

  @override
  void dispose() {
    _tempExtCtrl.dispose();
    _meteoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCanalisations() async {
    setState(() => _loading = true);
    final list = await _service.getCanalisations(widget.chantierDoc.$id);
    if (mounted) setState(() { _canalisations = list; _loading = false; });
  }

  // ── Calcul résine pour une ligne ─────────────
  double _calcResin(double longueur, double diametre, int passes) {
    return (longueur * math.pi * diametre * _epaisseur / 1000) * passes;
  }

  double get _totalLinear {
    double total = 0;
    for (final c in _canalisations) {
      final len    = double.tryParse(c.data['longueur'] as String? ?? '0') ?? 0;
      final passes = c.data['passes'] as int? ?? _desiredPasses;
      total += len * passes;
    }
    return total;
  }

  double get _totalResin {
    double total = 0;
    for (final c in _canalisations) {
      final len = double.tryParse(c.data['longueur'] as String? ?? '0') ?? 0;
      final dia = double.tryParse(c.data['diametre'] as String? ?? '100') ?? 100;
      final passes = c.data['passes'] as int? ?? _desiredPasses;
      total += _calcResin(len, dia, passes);
    }
    return total;
  }

  int get _recPasses {
    final rec = 3.0 / _epaisseur;
    return rec.ceil();
  }

  Future<void> _addCanalisation() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddCanalisationSheet(
        defaultPasses: _desiredPasses),
    );
    if (result == null) return;

    setState(() => _addingCanalisation = true);
    try {
      await _service.createCanalisation(
        chantierId: widget.chantierDoc.$id,
        label:      result['label'],
        longueur:   result['longueur'],
        diametre:   result['diametre'],
        passes:     result['passes'],
        userId:     widget.userId,
      );
      await _loadCanalisations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✓ ${_lang.t('pumpChantierCanalisationAddedMsg')}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${_lang.t('pumpChantierCreationErrorPrefix')} $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8)));
      }
    } finally {
      if (mounted) setState(() => _addingCanalisation = false);
    }
  }

  Future<void> _saveParams() async {
    // On met à jour les paramètres de base + les nouvelles données environnementales
    await _service.updateChantierParams(
      widget.chantierDoc.$id, _resinType,
      _epaisseur.toStringAsFixed(2), _desiredPasses);
      
    // Sauvegarde additionnelle des champs environnementaux dans Appwrite
    try {
      await _service.updateChantierEnv(
        widget.chantierDoc.$id, _tempExtCtrl.text.trim(), _meteoCtrl.text.trim());
    } catch (_) {
      // Si la méthode updateChantierEnv n'existe pas encore dans ton PumpService, 
      // tu pourras l'ajouter ou t'assurer qu'elle met à jour les attributs tempExt et meteo.
    }

    for (final c in _canalisations) {
      if (c.data['statut'] != 'termine') {
        await _service.updateCanalisation(c.$id, passes: _desiredPasses);
      }
    }
    _loadCanalisations();
  }

  Future<void> _generateGlobalReport() async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(
        color: Color(0xFF22D3EE))));
    try {
      final pdfSvc = PumpPdfService();
      final bytes  = await pdfSvc.generateGlobalReport(
        chantierDoc:    widget.chantierDoc,
        canalisations:  _canalisations,
        resinType:      _resinType,
        epaisseur:      _epaisseur,
        desiredPasses:  _desiredPasses,
        operateur:      widget.userName,
      );
      if (mounted) Navigator.pop(context);
      final storage  = PdfStorageService();
      final nomCh    = widget.chantierDoc.data['nom'] as String? ?? 'chantier';
      final filename = 'Rapport_${nomCh}_${DateTime.now().millisecondsSinceEpoch}';
      await storage.savePdf(bytes, filename);
      
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RapportViewerScreen(
            pdfBytes: bytes,
            title: _lang.t('pumpChantierGlobalReportTitle'),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_lang.t('pumpChantierPdfErrorPrefix')} $e'), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.chantierDoc.data;
    final terminees = _canalisations
      .where((c) => c.data['statut'] == 'termine').length;

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(ch['nom'] as String? ?? _lang.t('pumpChantierDefaultName'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open,
              color: Colors.orange, size: 20),
            tooltip: _lang.t('pumpChantierReportsTooltip'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PumpRapportsScreen(
                chantierPrefix: 'Rapport_${widget.chantierDoc.data['nom'] ?? ''}',
                chantierNom: widget.chantierDoc.data['nom'] as String?)))),
          if (terminees > 0)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf,
                color: Color(0xFF22D3EE), size: 20),
              onPressed: _generateGlobalReport),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            border: Border(bottom: BorderSide(
              color: Colors.white.withOpacity(0.06)))),
          child: Row(children: [
            Icon(Icons.location_on_outlined,
              color: Colors.grey[500], size: 12),
            const SizedBox(width: 4),
            Text('${ch['rue'] ?? ''}, ${ch['ville'] ?? ''}',
              style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const Spacer(),
            Icon(Icons.calendar_today_outlined,
              color: Colors.grey[700], size: 10),
            const SizedBox(width: 3),
            Text(ch['date'] as String? ?? '',
              style: TextStyle(color: Colors.grey[700], fontSize: 10)),
          ]),
        ),
        
        // ── Panneau paramètres globaux ────────────────
        _buildParamsPanel(),

        // ── Nouveau Panneau : Conditions Environnementales ──
        _buildEnvPanel(),

        // ── Tableau dimensionnement ─────────────
        _buildTableHeader(),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: Color(0xFF22D3EE)))
            : _canalisations.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.water_drop_outlined,
                    color: Colors.grey[700], size: 40),
                  const SizedBox(height: 10),
                  Text(_lang.t('pumpChantierNoCanalisationMsg'),
                    style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(_lang.t('pumpChantierTapToAddMsg'),
                    style: TextStyle(color: Colors.grey[700], fontSize: 11)),
                ]))
              : RefreshIndicator(
                  onRefresh: _loadCanalisations,
                  color: const Color(0xFF22D3EE),
                  child: SingleChildScrollView(
                    child: Column(children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildTable()),
                      _buildTotaux(),
                      const SizedBox(height: 80),
                    ]),
                  ),
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addingCanalisation ? null : _addCanalisation,
        backgroundColor: const Color(0xFF22D3EE),
        foregroundColor: Colors.black,
        icon: _addingCanalisation
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.add),
        label: Text(_addingCanalisation ? _lang.t('pumpChantierAddingLabel') : _lang.t('pumpChantierAddLineLabel'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildParamsPanel() {
    final resin   = _resins.firstWhere((r) => r['id'] == _resinType,
      orElse: () => _resins[0]);
    final epRec   = resin['epRec'] as double;
    final epMin   = resin['epMin'] as double;
    final epMax   = resin['epMax'] as double;
    final isWarn  = _epaisseur != epRec;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(
          color: Colors.white.withOpacity(0.06)))),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_lang.t('pumpChantierResinTypeLabel'), style: TextStyle(
              color: Colors.grey[500], fontSize: 8,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _resinType,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0D0D0D),
                  style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w700),
                  items: _resins.map((r) => DropdownMenuItem(
                    value: r['id'] as String,
                    child: Text(r['label'] as String))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final nr = _resins.firstWhere((r) => r['id'] == v);
                    setState(() {
                      _resinType = v;
                      _epaisseur = nr['epRec'] as double;
                      _desiredPasses = _recPasses;
                    });
                    _saveParams();
                  },
                ),
              ),
            ),
          ])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(_lang.t('pumpChantierEpPasseLabel'), style: TextStyle(
              color: Colors.grey[500], fontSize: 8,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Row(children: [
              _paramBox('${epRec.toStringAsFixed(2)}', Colors.grey, _lang.t('pumpChantierRecLabel')),
              const SizedBox(width: 6),
              _epaisseurInput(epMin, epMax, isWarn),
            ]),
            if (isWarn)
              Text('⚠ ${_lang.t('pumpChantierValueNotRecommendedMsg')}',
                style: const TextStyle(color: Colors.red,
                  fontSize: 8, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(_lang.t('pumpChantierPassesLabel'), style: TextStyle(
              color: Colors.grey[500], fontSize: 8,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Row(children: [
              _paramBox('$_recPasses', Colors.grey, _lang.t('pumpChantierRecLabel')),
              const SizedBox(width: 6),
              _passesInput(),
            ]),
          ]),
        ]),
      ]),
    );
  }

  // ── Panneau de saisie Environnement / Météo ──
  Widget _buildEnvPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(children: [
        const Icon(Icons.thermostat, color: Color(0xFF22D3EE), size: 16),
        const SizedBox(width: 8),
        Text(_lang.t('pumpChantierEnvironmentLabel'), style: TextStyle(color: Colors.grey[400], fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(width: 12),
        // Champ Température Extérieure
        Expanded(
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: _tempExtCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: _lang.t('pumpChantierTempExtHint'),
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: Colors.black.withOpacity(0.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              onSubmitted: (_) => _saveParams(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Champ Météo / Conditions
        Expanded(
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: _meteoCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: _lang.t('pumpChantierMeteoHint'),
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: Colors.black.withOpacity(0.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              onSubmitted: (_) => _saveParams(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _paramBox(String value, Color color, String sub) {
    return Container(
      width: 48, height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: TextStyle(color: color,
          fontSize: 11, fontWeight: FontWeight.w900)),
        Text(sub, style: TextStyle(color: color.withOpacity(0.5),
          fontSize: 7)),
      ]),
    );
  }

  Widget _epaisseurInput(double epMin, double epMax, bool isWarn) {
    return Container(
      width: 58, height: 38,
      decoration: BoxDecoration(
        color: isWarn
          ? Colors.red.withOpacity(0.1)
          : const Color(0xFF22D3EE).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isWarn
          ? Colors.red.withOpacity(0.3)
          : const Color(0xFF22D3EE).withOpacity(0.3))),
      child: TextField(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isWarn ? Colors.red : const Color(0xFF22D3EE),
          fontSize: 12, fontWeight: FontWeight.w900),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero),
        controller: TextEditingController(
          text: _epaisseur.toStringAsFixed(2))
          ..selection = TextSelection.collapsed(
            offset: _epaisseur.toStringAsFixed(2).length),
        onSubmitted: (v) {
          double val = double.tryParse(v) ?? _epaisseur;
          val = val.clamp(epMin, epMax);
          setState(() => _epaisseur = val);
          _saveParams();
        },
      ),
    );
  }

  Widget _passesInput() {
    return Container(
      width: 58, height: 38,
      decoration: BoxDecoration(
        color: _desiredPasses != _recPasses
          ? Colors.red.withOpacity(0.1)
          : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _desiredPasses != _recPasses
          ? Colors.red.withOpacity(0.3)
          : Colors.white.withOpacity(0.1))),
      child: TextField(
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _desiredPasses != _recPasses
            ? Colors.red : Colors.white,
          fontSize: 12, fontWeight: FontWeight.w900),
        decoration: const InputDecoration(
          border: InputBorder.none, contentPadding: EdgeInsets.zero),
        controller: TextEditingController(
          text: '$_desiredPasses'),
        onSubmitted: (v) {
          final val = int.tryParse(v) ?? _desiredPasses;
          if (val < 1) return;
          setState(() => _desiredPasses = val);
          _saveParams();
        },
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(
          color: Colors.white.withOpacity(0.06)))),
      child: Row(children: [
        const Icon(Icons.table_chart_outlined,
          color: Color(0xFF22D3EE), size: 13),
        const SizedBox(width: 6),
        Text('${_lang.t('pumpChantierDimensioningTitle')} (${_canalisations.length})',
          style: TextStyle(color: Colors.grey[400], fontSize: 9,
            fontWeight: FontWeight.w900, letterSpacing: 2)),
      ]),
    );
  }

  Widget _buildTable() {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(const Color(0xFF0D0D0D)),
      dataRowColor: WidgetStateProperty.resolveWith((_) =>
        const Color(0xFF050505)),
      border: TableBorder(horizontalInside: BorderSide(
        color: Colors.white.withOpacity(0.04))),
      columnSpacing: 14,
      headingRowHeight: 32,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 64,
      columns: _buildColumns(),
      rows: _canalisations.asMap().entries.map((e) =>
        _buildRow(e.key, e.value)).toList(),
    );
  }

  List<DataColumn> _buildColumns() {
    final s = TextStyle(color: Colors.grey[500], fontSize: 9,
      fontWeight: FontWeight.w900, letterSpacing: 1.5);
    return [
      DataColumn(label: Text('#', style: s)),
      DataColumn(label: Text(_lang.t('pumpChantierColLabel'), style: s)),
      DataColumn(label: Text(_lang.t('pumpChantierColLong'), style: s)),
      DataColumn(label: Text('Ø (mm)', style: s)),
      DataColumn(label: Text(_lang.t('pumpChantierColPasses'), style: s)),
      DataColumn(label: Text(_lang.t('pumpChantierColResine'), style: s)),
      DataColumn(label: Text(_lang.t('pumpChantierColAction'), style: s)),
    ];
  }

  DataRow _buildRow(int idx, models.Document doc) {
    final d      = doc.data;
    final label  = d['label']    as String? ?? '';
    final lonStr = d['longueur'] as String? ?? '0';
    final diaStr = d['diametre'] as String? ?? '100';
    final passes = d['passes']   as int?    ?? _desiredPasses;
    final statut = d['statut']   as String? ?? 'en_attente';
    final lon    = double.tryParse(lonStr) ?? 0;
    final dia    = double.tryParse(diaStr) ?? 100;
    final resin  = _calcResin(lon, dia, passes);
    final partA  = resin * (2/3);
    final partB  = resin * (1/3);
    final isDone = statut == 'termine';

    return DataRow(cells: [
      DataCell(Text('${idx + 1}', style: TextStyle(
        color: Colors.grey[600], fontSize: 11))),
      DataCell(SizedBox(width: 100, child: Text(label,
        style: const TextStyle(color: Colors.white,
          fontSize: 12, fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis))),
      DataCell(Text(lonStr, style: TextStyle(
        color: Colors.grey[400], fontSize: 11))),
      DataCell(Text('DN$diaStr', style: TextStyle(
        color: Colors.grey[400], fontSize: 11))),
      DataCell(Text('$passes', style: TextStyle(
        color: passes != _desiredPasses
          ? Colors.red : Colors.white,
        fontSize: 12, fontWeight: FontWeight.w700))),
      DataCell(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${resin.toStringAsFixed(2)} L',
          style: const TextStyle(color: Colors.purple,
            fontSize: 11, fontWeight: FontWeight.w700)),
        Text('A:${partA.toStringAsFixed(2)} B:${partB.toStringAsFixed(2)}',
          style: TextStyle(color: Colors.grey[600], fontSize: 8)),
      ])),
      DataCell(isDone
        ? Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
              child: Text('✓ ${_lang.t('pumpChantierDoneLabel')}',
                style: const TextStyle(color: Colors.green,
                  fontSize: 9, fontWeight: FontWeight.w900))),
            const SizedBox(height: 3),
            GestureDetector(
              onTap: () => _generateRowReport(idx, doc),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
                child: Text('📄 ${_lang.t('pumpChantierReportLabel')}',
                  style: const TextStyle(color: Colors.blue,
                    fontSize: 9, fontWeight: FontWeight.w900)))),
          ])
        : Row(children: [
            GestureDetector(
              onTap: () => _startOperation(idx, doc),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF0891B2), Color(0xFF3B82F6)]),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(
                    color: const Color(0xFF22D3EE).withOpacity(0.3),
                    blurRadius: 8)]),
                child: Text(
                  statut == 'en_cours' ? '▶ ${_lang.t('pumpChantierContinueBtn')}' : '▶ ${_lang.t('pumpChantierStartBtn')}',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 9, fontWeight: FontWeight.w900)))),
            const SizedBox(width: 4),
            if (widget.userRole == AppRoles.superAdmin ||
                widget.userRole == AppRoles.admin)
              GestureDetector(
                onTap: () async {
                  await _service.deleteCanalisation(doc.$id);
                  _loadCanalisations();
                },
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.delete_outline,
                    color: Colors.red[400], size: 13))),
          ])),
    ]);
  }

  Widget _buildTotaux() {
    final totalLin  = _totalLinear;
    final totalRes  = _totalResin;
    final partA     = totalRes * (2/3);
    final partB     = totalRes * (1/3);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF22D3EE).withOpacity(0.07),
          Colors.black.withOpacity(0.3)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Row(children: [
        Expanded(child: Column(children: [
          Text(_lang.t('pumpChantierLinearTotalLabel'), style: TextStyle(
            color: Colors.grey[500], fontSize: 8,
            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(totalLin.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white,
                fontSize: 24, fontWeight: FontWeight.w900)),
            const Text(' m', style: TextStyle(
              color: Color(0xFF22D3EE), fontSize: 14,
              fontWeight: FontWeight.w700)),
          ]),
        ])),
        Container(width: 1, height: 50,
          color: Colors.white.withOpacity(0.1)),
        Expanded(child: Column(children: [
          Text(_lang.t('pumpChantierResinQtyLabel'), style: TextStyle(
            color: Colors.grey[500], fontSize: 8,
            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(totalRes.toStringAsFixed(2),
              style: const TextStyle(color: Colors.purple,
                fontSize: 24, fontWeight: FontWeight.w900)),
            const Text(' L', style: TextStyle(
              color: Colors.purple, fontSize: 14,
              fontWeight: FontWeight.w700)),
          ]),
          Text('A: ${partA.toStringAsFixed(2)} | B: ${partB.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey[500],
              fontSize: 9, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }

  void _startOperation(int idx, models.Document doc) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PumpOperationScreen(
        canalisationDoc: doc,
        chantierDoc:     widget.chantierDoc,
        epaisseur:       _epaisseur,
        resinType:       _resinType,
        userName:        widget.userName,
      ))).then((_) => _loadCanalisations());
  }

  Future<void> _generateRowReport(int idx, models.Document doc) async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(
        color: Color(0xFF22D3EE))));
    try {
      final pdfSvc = PumpPdfService();
      final bytes  = await pdfSvc.generateRowReport(
        chantierDoc:  widget.chantierDoc,
        canalisation: doc,
        resinType:    _resinType,
        epaisseur:    _epaisseur,
        operateur:    widget.userName,
        calcResin:    (lon, dia, pas) => _calcResin(lon, dia, pas),
      );
      if (mounted) Navigator.pop(context);
      
      final label = doc.data['label'] as String? ?? 'canal_${idx+1}';
      
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RapportViewerScreen(
            pdfBytes: bytes,
            title: '${_lang.t('pumpChantierRowReportTitlePrefix')} $label',
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_lang.t('pumpChantierPdfErrorPrefix')} $e'), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    }
  }
}

class _AddCanalisationSheet extends StatefulWidget {
  final int defaultPasses;
  const _AddCanalisationSheet({required this.defaultPasses});
  @override
  State<_AddCanalisationSheet> createState() => _AddCanalisationSheetState();
}

class _AddCanalisationSheetState extends State<_AddCanalisationSheet> {
  final _lang = LangService();
  final _labelCtrl = TextEditingController();
  final _lonCtrl   = TextEditingController(text: '10');
  final _diaCtrl   = TextEditingController(text: '100');
  late int _passes;

  @override
  void initState() { super.initState(); _passes = widget.defaultPasses; }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(_lang.t('pumpChantierNewCanalisationTitle'), style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900,
          fontSize: 13, letterSpacing: 2)),
        const SizedBox(height: 20),
        _field(_labelCtrl, _lang.t('pumpChantierLabelOptionalHint'), Icons.label_outline),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field(_lonCtrl, _lang.t('pumpChantierLongueurHint'),
            Icons.straighten, isNumeric: true)),
          const SizedBox(width: 10),
          Expanded(child: _field(_diaCtrl, _lang.t('pumpChantierDiametreHint'),
            Icons.circle_outlined, isNumeric: true)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('${_lang.t('pumpChantierPassesFieldLabel')} : ', style: TextStyle(
            color: Colors.grey[400], fontSize: 12)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () { if (_passes > 1) setState(() => _passes--); },
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.remove,
                color: Colors.white, size: 16))),
          const SizedBox(width: 12),
          Text('$_passes', style: const TextStyle(color: Colors.white,
            fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _passes++),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add,
                color: Color(0xFF22D3EE), size: 16))),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context, {
                'label':    _labelCtrl.text.trim(),
                'longueur': _lonCtrl.text.trim(),
                'diametre': _diaCtrl.text.trim(),
                'passes':   _passes,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            child: Text(_lang.t('pumpChantierAddBtn'), style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 13,
              letterSpacing: 2)),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool isNumeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 16),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}