// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bzvision_service.dart';
import '../services/pdf_service.dart';
import '../services/app_roles.dart';
import '../widgets/lang_selector.dart';
import '../widgets/tutorial_overlay.dart';
import 'bzvision_inspection_screen.dart';
import 'bzvision_camera_screen.dart';
import 'bzvision_reseau_screen.dart';
import 'pdf_viewer_screen.dart';
import 'package:printing/printing.dart';

class BzVisionChantierScreen extends StatefulWidget {
  final models.Document chantierDoc;
  final String userRole, userId, userName;
  const BzVisionChantierScreen({super.key,
    required this.chantierDoc, required this.userRole,
    required this.userId, required this.userName});
  @override
  State<BzVisionChantierScreen> createState() => _BzVisionChantierScreenState();
}

class _BzVisionChantierScreenState extends State<BzVisionChantierScreen> {
  final _service = BzVisionService();
  List<models.Document> _canalisations = [];
  List<List<models.Document>> _inspectionsParCanalisation = [];
  bool _loading   = true;
  bool _fromCache = false;

  final _keyAdd     = GlobalKey();
  final _keyRapport = GlobalKey();
  final _keyFin     = GlobalKey();
  final _keyList    = GlobalKey();
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    _loadCanalisations();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final show = await TutorialOverlay.shouldShow('bzvision_chantier');
    if (mounted) setState(() => _showTutorial = show);
  }

  Future<void> _loadCanalisations() async {
    setState(() => _loading = true);
    final chantierId = widget.chantierDoc.$id;
    try {
      final list = await _service.getCanalisations(chantierId);
      final inspections = await Future.wait(list.map((c) => _service.getInspections(c.$id)));
      // Sauvegarde en cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bzvision_canalisations_$chantierId',
        jsonEncode(list.map((d) => {'id': d.$id, 'data': d.data}).toList()));
      await prefs.setString('bzvision_inspections_$chantierId',
        jsonEncode(inspections.map((insList) =>
          insList.map((d) => {'id': d.$id, 'data': d.data}).toList()).toList()));
      if (mounted) setState(() {
        _canalisations = list;
        _inspectionsParCanalisation = inspections;
        _fromCache = false;
        _loading   = false;
      });
    } catch (_) {
      await _loadFromCache(chantierId);
    }
  }

  Future<void> _loadFromCache(String chantierId) async {
    final prefs = await SharedPreferences.getInstance();
    models.Document _docFrom(Map e) => models.Document.fromMap({
      '\$id': e['id'], '\$collectionId': '', '\$databaseId': '',
      '\$createdAt': '', '\$updatedAt': '', '\$permissions': [],
      ...Map<String, dynamic>.from(e['data']),
    });
    final rawCan  = prefs.getString('bzvision_canalisations_$chantierId') ?? '[]';
    final rawIns  = prefs.getString('bzvision_inspections_$chantierId')   ?? '[]';
    final canList = (jsonDecode(rawCan) as List).map<models.Document>((e) => _docFrom(e)).toList();
    final insList = (jsonDecode(rawIns) as List).map<List<models.Document>>(
      (group) => (group as List).map<models.Document>((e) => _docFrom(e)).toList()).toList();
    if (mounted) setState(() {
      _canalisations = canList;
      _inspectionsParCanalisation = insList;
      _fromCache = true;
      _loading   = false;
    });
  }

  Future<void> _editCanalisation(models.Document doc) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditCanalisationSheet(doc: doc),
    );
    if (result != null) {
      await _service.updateCanalisation(
        docId:          doc.$id,
        nom:            result['nom']!,
        diametre:       result['diametre']!,
        longueur:       result['longueur']!,
        materiau:       result['materiau']!,
        noeudAmont:     result['noeudAmont']!,
        noeudAval:      result['noeudAval']!,
        forme:          result['forme']!,
        sensEcoulement: result['sensEcoulement']!,
        typeEffluent:   result['typeEffluent']!,
        profondeurAmont:result['profondeurAmont']!,
        profondeurAval: result['profondeurAval']!,
      );
      _loadCanalisations();
    }
  }

  Future<void> _showAddCanalisation() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _AddCanalisationSheet(),
    );
    if (result != null) {
      try {
        await _service.createCanalisation(
          chantierId:      widget.chantierDoc.$id,
          nom:             result['nom']!,
          diametre:        result['diametre']!,
          longueur:        result['longueur']!,
          materiau:        result['materiau']!,
          noeudAmont:      result['noeudAmont']!,
          noeudAval:       result['noeudAval']!,
          forme:           result['forme']!,
          sensEcoulement:  result['sensEcoulement']!,
          typeEffluent:    result['typeEffluent'] ?? 'EU',
          profondeurAmont: result['profondeurAmont'] ?? '',
          profondeurAval:  result['profondeurAval'] ?? '',
          statut:          'a_inspecter',
          observations:    '',
        );
        _loadCanalisations();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur création : $e',
            style: const TextStyle(color: Colors.white, fontSize: 11)),
          backgroundColor: Colors.red.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> _generateAndOpenReport({bool finChantier = false}) async {
    if (finChantier) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D0D0D),
          title: const Text('Fin du chantier',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          content: const Text(
            'Voulez-vous clôturer ce chantier et générer le rapport final ?',
            style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black),
              child: const Text('Clôturer & Générer',
                style: TextStyle(fontWeight: FontWeight.w900))),
          ],
        ),
      );
      if (confirm != true) return;
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF22D3EE))));

    try {
      final inspectionsParCanalisation = await Future.wait(
        _canalisations.map((c) => _service.getInspections(c.$id)));
      setState(() => _inspectionsParCanalisation = inspectionsParCanalisation);
      final pdfService = PdfService();
      final pdfData    = await pdfService.generateChantierReport(
        chantierDoc: widget.chantierDoc,
        canalisations: _canalisations,
        inspectionsParCanalisation: inspectionsParCanalisation,
      );
      final dir        = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${dir.path}/bzbots_reports');
      if (!await reportsDir.exists()) await reportsDir.create(recursive: true);
      final nomChantier = (widget.chantierDoc.data['nom'] as String? ?? 'chantier')
        .replaceAll(' ', '_');
      final filename = 'Rapport_${nomChantier}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfPath  = '${reportsDir.path}/$filename';
      await File(pdfPath).writeAsBytes(pdfData);
      if (mounted) Navigator.pop(context); // ferme le loader
      if (finChantier) {
        await _service.updateChantierStatut(widget.chantierDoc.$id, 'termine');
      }
      if (mounted) {
        await showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0D0D0D),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => _RapportReadySheet(
            pdfPath: pdfPath,
            filename: filename,
            nomChantier: nomChantier,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur PDF : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  Color _statutColor(String s) => switch (s) {
    'inspecte' => Colors.green,
    'en_cours' => const Color(0xFFEAB308),
    _ => Colors.orange,
  };

  String _statutLabel(String s) => switch (s) {
    'inspecte' => 'Inspecté',
    'en_cours' => 'En cours',
    _ => 'À inspecter',
  };

  IconData _statutIcon(String s) => switch (s) {
    'inspecte' => Icons.check_circle_outline,
    'en_cours' => Icons.timelapse,
    _ => Icons.schedule,
  };

  @override
  Widget build(BuildContext context) {
    final chantier   = widget.chantierDoc.data;
    final inspectees = _canalisations.where((c) => c.data['statut'] == 'inspecte').length;

    return Stack(children: [
      Scaffold(
        backgroundColor: const Color(0xFF050505),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.4),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
          title: Row(children: [
            Expanded(child: Text(chantier['nom'] as String? ?? 'Chantier',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
              overflow: TextOverflow.ellipsis)),
            if (_fromCache) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.4))),
                child: const Text('CACHE', style: TextStyle(
                  color: Colors.orange, fontSize: 9, fontWeight: FontWeight.w900,
                  letterSpacing: 1))),
            ],
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_tree_outlined,
                color: Color(0xFF22D3EE), size: 20),
              tooltip: 'Vue réseau 3D',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BzVisionReseauScreen(
                  chantierDoc: widget.chantierDoc,
                  canalisations: _canalisations,
                  inspectionsParCanalisation: _inspectionsParCanalisation,
                )))),
            IconButton(
              icon: const Icon(Icons.videocam, color: Color(0xFF22D3EE), size: 22),
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BzVisionCameraScreen()))),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white54, size: 20),
              tooltip: 'Revoir le tutoriel',
              onPressed: () async {
                await TutorialOverlay.reset('bzvision_chantier');
                if (mounted) setState(() => _showTutorial = true);
              }),
            const LangSelector(), const SizedBox(width: 8),
          ],
        ),
        body: Column(children: [
          // Infos chantier
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06)))),
            child: Column(children: [
              Row(children: [
                Icon(Icons.location_on_outlined, color: Colors.grey[500], size: 13),
                const SizedBox(width: 4),
                Expanded(child: Text(chantier['adresse'] as String? ?? '',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12))),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.business_outlined, color: Colors.grey[500], size: 13),
                const SizedBox(width: 4),
                Text(chantier['client'] as String? ?? '',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                const Spacer(),
                Icon(Icons.calendar_today_outlined, color: Colors.grey[700], size: 11),
                const SizedBox(width: 4),
                Text(chantier['date'] as String? ?? '',
                  style: TextStyle(color: Colors.grey[700], fontSize: 11)),
              ]),
            ]),
          ),

          // Header + boutons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06)))),
            child: Row(children: [
              Icon(Icons.water, color: const Color(0xFF22D3EE), size: 14),
              const SizedBox(width: 8),
              Text('CANALISATIONS (${_canalisations.length})',
                style: TextStyle(color: Colors.grey[400], fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const Spacer(),
              if (inspectees > 0) ...[
                GestureDetector(
                  key: _keyRapport,
                  onTap: () => _generateAndOpenReport(finChantier: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
                    child: const Row(children: [
                      Icon(Icons.picture_as_pdf, color: Color(0xFF22D3EE), size: 12),
                      SizedBox(width: 4),
                      Text('Rapport', style: TextStyle(color: Color(0xFF22D3EE),
                        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ]))),
                const SizedBox(width: 8),
                GestureDetector(
                  key: _keyFin,
                  onTap: () => _generateAndOpenReport(finChantier: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
                      borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.check_circle_outline, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('Fin du chantier', style: TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ]))),
              ],
            ]),
          ),

          // Liste des cards
          Expanded(
            key: _keyList,
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
              : _canalisations.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.water_outlined, color: Colors.grey[700], size: 48),
                    const SizedBox(height: 12),
                    Text('Aucune canalisation\nAppuyez sur + pour en ajouter',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ]))
                : RefreshIndicator(
                    onRefresh: _loadCanalisations,
                    color: const Color(0xFF22D3EE),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _canalisations.length,
                      itemBuilder: (_, i) => _buildCanalCard(i, _canalisations[i]))),
          ),
        ]),

        floatingActionButton: FloatingActionButton.extended(
          key: _keyAdd,
          onPressed: _showAddCanalisation,
          backgroundColor: const Color(0xFF22D3EE),
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),

      if (_showTutorial)
        TutorialOverlay(
          tutorialKey: 'bzvision_chantier',
          onComplete: () => setState(() => _showTutorial = false),
          steps: [
            TutorialStep(
              targetKey: _keyList,
              title: 'Liste des canalisations',
              description: 'Vos canalisations apparaissent ici sous forme de cartes. Appuyez sur INSPECTER pour lancer une inspection.',
              bubblePosition: TutorialBubblePosition.bottom),
            TutorialStep(
              targetKey: _keyAdd,
              title: 'Ajouter une canalisation',
              description: 'Appuyez ici pour ajouter une nouvelle canalisation à inspecter sur ce chantier.',
              bubblePosition: TutorialBubblePosition.top),
            TutorialStep(
              targetKey: _keyRapport,
              title: 'Générer un rapport',
              description: 'Générez un rapport PDF complet avec toutes les inspections et captures du chantier.',
              bubblePosition: TutorialBubblePosition.bottom),
            TutorialStep(
              targetKey: _keyFin,
              title: 'Fin du chantier',
              description: 'Clôturez définitivement le chantier et archivez le rapport final en PDF.',
              bubblePosition: TutorialBubblePosition.bottom),
          ],
        ),
    ]);
  }

  Widget _buildCanalCard(int index, models.Document doc) {
    final d      = doc.data;
    final statut = d['statut'] as String? ?? 'a_inspecter';
    final color  = _statutColor(statut);
    final nom    = d['nom']           as String? ?? 'Canalisation ${index + 1}';
    final long   = d['longueur']      as String? ?? '—';
    final dia    = d['diametre']      as String? ?? '—';
    final amont  = d['noeudAmont']    as String? ?? '—';
    final aval   = d['noeudAval']     as String? ?? '—';
    final mat    = d['materiau']      as String? ?? '—';
    final forme      = d['forme']          as String? ?? '—';
    final ecoul      = d['sensEcoulement'] as String? ?? '—';
    final effluent   = d['typeEffluent']   as String? ?? '—';
    final profAmont  = d['profondeurAmont'] as String? ?? '';
    final profAval   = d['profondeurAval']  as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color.withOpacity(0.6), width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)]),
      child: Column(children: [

        // En-tête
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)))),
            const SizedBox(width: 10),
            Expanded(child: Text(nom,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_statutIcon(statut), color: color, size: 10),
                const SizedBox(width: 4),
                Text(_statutLabel(statut),
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
              ])),
          ]),
        ),

        // Infos techniques
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: [
            Row(children: [
              _infoChip(Icons.straighten,       '$long m', Colors.white54,           'Longueur'),
              const SizedBox(width: 6),
              _infoChip(Icons.circle_outlined,   'DN $dia', Colors.white54,           'Diamètre'),
              const SizedBox(width: 6),
              _infoChip(Icons.layers_outlined,   mat,       const Color(0xFFEAB308),  'Matière'),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _infoChip(Icons.arrow_forward,           amont, const Color(0xFF22D3EE), 'Amont'),
              const SizedBox(width: 6),
              _infoChip(Icons.arrow_back,              aval,  const Color(0xFFA855F7), 'Aval'),
              const SizedBox(width: 6),
              _infoChip(Icons.water_drop_outlined,     ecoul, const Color(0xFF3B82F6), 'Écoulement'),
            ]),
            if (forme.isNotEmpty && forme != '—') ...[
              const SizedBox(height: 6),
              Row(children: [
                _infoChip(Icons.shape_line_outlined, forme, Colors.white38, 'Forme'),
                const SizedBox(width: 6),
                _infoChip(Icons.opacity, effluent, const Color(0xFF06B6D4), 'Effluent'),
                const SizedBox(width: 6),
                if (profAmont.isNotEmpty || profAval.isNotEmpty)
                  _infoChip(Icons.vertical_align_bottom, '${profAmont.isNotEmpty ? profAmont : '—'}/${profAval.isNotEmpty ? profAval : '—'} m', Colors.white38, 'Prof. A/V')
                else
                  const Expanded(child: SizedBox()),
              ]),
            ],
          ]),
        ),

        // Boutons action
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BzVisionInspectionScreen(
                    canalisationDoc: doc,
                    chantierDoc:     widget.chantierDoc,
                    userRole:        widget.userRole,
                    userId:          widget.userId,
                    userName:        widget.userName,
                  ))).then((_) => _loadCanalisations()),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.play_arrow, color: Color(0xFF22D3EE), size: 16),
                    SizedBox(width: 6),
                    Text('INSPECTER', style: TextStyle(color: Color(0xFF22D3EE),
                      fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ])))),
            if (widget.userRole == AppRoles.superAdmin ||
                widget.userRole == AppRoles.admin) ...[
              const SizedBox(width: 8),
              // Bouton modifier
              GestureDetector(
                onTap: () => _editCanalisation(doc),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.2))),
                  child: Icon(Icons.edit_outlined,
                    color: Colors.orange[400], size: 16))),
              const SizedBox(width: 8),
              // Bouton supprimer
              GestureDetector(
                onTap: () async {
                  await _service.deleteCanalisation(doc.$id);
                  _loadCanalisations();
                },
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.2))),
                  child: Icon(Icons.delete_outline, color: Colors.red[400], size: 16))),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String value, Color color, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.15))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.grey[700],
            fontSize: 8, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Row(children: [
            Icon(icon, color: color, size: 10),
            const SizedBox(width: 3),
            Expanded(child: Text(value,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      ),
    );
  }
}

// ── Formulaire ajout canalisation ────────────────
class _AddCanalisationSheet extends StatefulWidget {
  const _AddCanalisationSheet();
  @override
  State<_AddCanalisationSheet> createState() => _AddCanalisationSheetState();
}

class _AddCanalisationSheetState extends State<_AddCanalisationSheet> {
  final _nomCtrl      = TextEditingController();
  final _diaCtr       = TextEditingController();
  final _longCtr      = TextEditingController();
  final _matCtr       = TextEditingController();
  final _amontCtr     = TextEditingController();
  final _avalCtr      = TextEditingController();
  final _profAmontCtr = TextEditingController();
  final _profAvalCtr  = TextEditingController();
  String _forme          = 'Circulaire';
  String _sensEcoulement = 'Gravitaire';
  String _typeEffluent   = 'EU';
  final _formes      = ['Circulaire', 'Ovoïde', 'Rectangulaire', 'Autre'];
  final _ecoulements = ['Gravitaire', 'En charge', 'Inconnu'];
  final _effluents   = ['EU', 'EP', 'Unitaire', 'Industriel', 'Inconnu'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('NOUVELLE CANALISATION', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
          const SizedBox(height: 20),
          _field(_nomCtrl, 'Libellé / Référence *', Icons.label_outline),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_longCtr, 'Longueur (m)', Icons.straighten)),
            const SizedBox(width: 10),
            Expanded(child: _field(_diaCtr, 'Diamètre (mm)', Icons.circle_outlined)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_amontCtr, 'Nœud amont', Icons.arrow_forward)),
            const SizedBox(width: 10),
            Expanded(child: _field(_avalCtr, 'Nœud aval', Icons.arrow_back)),
          ]),
          const SizedBox(height: 10),
          _field(_matCtr, 'Matière (PVC, fonte...)', Icons.layers_outlined),
          const SizedBox(height: 10),
          _dropdown('Forme', _formes, _forme, (v) => setState(() => _forme = v!)),
          const SizedBox(height: 10),
          _dropdown("Sens d'écoulement", _ecoulements, _sensEcoulement,
            (v) => setState(() => _sensEcoulement = v!)),
          const SizedBox(height: 10),
          _dropdown("Type d'effluent", _effluents, _typeEffluent,
            (v) => setState(() => _typeEffluent = v!)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_profAmontCtr, 'Prof. radier amont (m)', Icons.vertical_align_top)),
            const SizedBox(width: 10),
            Expanded(child: _field(_profAvalCtr, 'Prof. radier aval (m)', Icons.vertical_align_bottom)),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_nomCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'nom': _nomCtrl.text.trim(),
                  'longueur': _longCtr.text.trim(),
                  'diametre': _diaCtr.text.trim(),
                  'noeudAmont': _amontCtr.text.trim(),
                  'noeudAval': _avalCtr.text.trim(),
                  'materiau': _matCtr.text.trim(),
                  'forme': _forme,
                  'sensEcoulement': _sensEcoulement,
                  'typeEffluent': _typeEffluent,
                  'profondeurAmont': _profAmontCtr.text.trim(),
                  'profondeurAval': _profAvalCtr.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('AJOUTER', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 16),
        filled: true,
        fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
    );
  }

  Widget _dropdown(String label, List<String> items, String value,
      ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          dropdownColor: const Color(0xFF0D0D0D),
          style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w600),
          hint: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Bottom sheet rapport prêt ─────────────────────────────────────────────────
class _RapportReadySheet extends StatelessWidget {
  final String pdfPath;
  final String filename;
  final String nomChantier;

  const _RapportReadySheet({
    required this.pdfPath,
    required this.filename,
    required this.nomChantier,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          // Icône succès
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green.withOpacity(0.4))),
            child: const Icon(Icons.picture_as_pdf,
              color: Colors.green, size: 32)),
          const SizedBox(height: 14),
          const Text('Rapport généré !',
            style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(filename,
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
            textAlign: TextAlign.center),
          const SizedBox(height: 4),
          // Chemin de sauvegarde
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: Row(children: [
              const Icon(Icons.folder_outlined,
                color: Color(0xFF22D3EE), size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Stocké dans : Documents/bzbots_reports/',
                style: TextStyle(
                  color: Colors.grey[400], fontSize: 10,
                  fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
            ])),
          const SizedBox(height: 16),
          // Boutons
          Row(children: [
            // Ouvrir
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      path: pdfPath,
                      title: 'Rapport_$nomChantier')));
                },
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Ouvrir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22D3EE),
                  side: BorderSide(
                    color: const Color(0xFF22D3EE).withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)))),
            const SizedBox(width: 10),
            // Partager
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final bytes = await File(pdfPath).readAsBytes();
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: filename);
                },
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Partager',
                  style: TextStyle(fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22D3EE),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)))),
          ]),
          const SizedBox(height: 10),
          // Bouton Fermer
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer',
                style: TextStyle(color: Colors.grey, fontSize: 13)))),
        ]));
  }
}

// ── Formulaire édition canalisation ──────────────
class _EditCanalisationSheet extends StatefulWidget {
  final models.Document doc;
  const _EditCanalisationSheet({required this.doc});
  @override
  State<_EditCanalisationSheet> createState() => _EditCanalisationSheetState();
}

class _EditCanalisationSheetState extends State<_EditCanalisationSheet> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _diaCtr;
  late final TextEditingController _longCtr;
  late final TextEditingController _matCtr;
  late final TextEditingController _amontCtr;
  late final TextEditingController _avalCtr;
  late final TextEditingController _profAmontCtr;
  late final TextEditingController _profAvalCtr;
  late String _forme;
  late String _sensEcoulement;
  late String _typeEffluent;

  final _formes      = ['Circulaire', 'Ovoïde', 'Rectangulaire', 'Autre'];
  final _ecoulements = ['Gravitaire', 'En charge', 'Inconnu'];
  final _effluents   = ['EU', 'EP', 'Unitaire', 'Industriel', 'Inconnu'];

  @override
  void initState() {
    super.initState();
    final d = widget.doc.data;
    _nomCtrl      = TextEditingController(text: d['nom']            as String? ?? '');
    _diaCtr       = TextEditingController(text: d['diametre']       as String? ?? '');
    _longCtr      = TextEditingController(text: d['longueur']       as String? ?? '');
    _matCtr       = TextEditingController(text: d['materiau']       as String? ?? '');
    _amontCtr     = TextEditingController(text: d['noeudAmont']     as String? ?? '');
    _avalCtr      = TextEditingController(text: d['noeudAval']      as String? ?? '');
    _profAmontCtr = TextEditingController(text: d['profondeurAmont']as String? ?? '');
    _profAvalCtr  = TextEditingController(text: d['profondeurAval'] as String? ?? '');
    _forme          = d['forme']          as String? ?? 'Circulaire';
    _sensEcoulement = d['sensEcoulement'] as String? ?? 'Gravitaire';
    _typeEffluent   = d['typeEffluent']   as String? ?? 'EU';
    // Valeurs de sécurité si hors liste
    if (!_formes.contains(_forme))           _forme = 'Circulaire';
    if (!_ecoulements.contains(_sensEcoulement)) _sensEcoulement = 'Gravitaire';
    if (!_effluents.contains(_typeEffluent)) _typeEffluent = 'EU';
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _diaCtr.dispose(); _longCtr.dispose();
    _matCtr.dispose(); _amontCtr.dispose(); _avalCtr.dispose();
    _profAmontCtr.dispose(); _profAvalCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('MODIFIER LA CANALISATION', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900,
            fontSize: 13, letterSpacing: 2)),
          const SizedBox(height: 20),
          _field(_nomCtrl, 'Libellé / Référence *', Icons.label_outline),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_longCtr, 'Longueur (m)', Icons.straighten)),
            const SizedBox(width: 10),
            Expanded(child: _field(_diaCtr, 'Diamètre (mm)', Icons.circle_outlined)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_amontCtr, 'Nœud amont', Icons.arrow_forward)),
            const SizedBox(width: 10),
            Expanded(child: _field(_avalCtr, 'Nœud aval', Icons.arrow_back)),
          ]),
          const SizedBox(height: 10),
          _field(_matCtr, 'Matière (PVC, fonte...)', Icons.layers_outlined),
          const SizedBox(height: 10),
          _dropdown('Forme', _formes, _forme,
            (v) => setState(() => _forme = v!)),
          const SizedBox(height: 10),
          _dropdown("Sens d'écoulement", _ecoulements, _sensEcoulement,
            (v) => setState(() => _sensEcoulement = v!)),
          const SizedBox(height: 10),
          _dropdown("Type d'effluent", _effluents, _typeEffluent,
            (v) => setState(() => _typeEffluent = v!)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_profAmontCtr,
              'Prof. radier amont (m)', Icons.vertical_align_top)),
            const SizedBox(width: 10),
            Expanded(child: _field(_profAvalCtr,
              'Prof. radier aval (m)', Icons.vertical_align_bottom)),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_nomCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'nom':            _nomCtrl.text.trim(),
                  'longueur':       _longCtr.text.trim(),
                  'diametre':       _diaCtr.text.trim(),
                  'noeudAmont':     _amontCtr.text.trim(),
                  'noeudAval':      _avalCtr.text.trim(),
                  'materiau':       _matCtr.text.trim(),
                  'forme':          _forme,
                  'sensEcoulement': _sensEcoulement,
                  'typeEffluent':   _typeEffluent,
                  'profondeurAmont':_profAmontCtr.text.trim(),
                  'profondeurAval': _profAvalCtr.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('ENREGISTRER', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) =>
    TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 16),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))));

  Widget _dropdown(String label, List<String> items, String value,
      ValueChanged<String?> onChanged) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          dropdownColor: const Color(0xFF0D0D0D),
          style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w600),
          items: items.map((i) =>
            DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged)));
}
