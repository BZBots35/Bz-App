// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/bzvision_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BzVisionReseauScreen — Vue 2.5D du réseau de canalisations par chantier
// ══════════════════════════════════════════════════════════════════════════════
class BzVisionReseauScreen extends StatefulWidget {
  final models.Document chantierDoc;
  final List<models.Document> canalisations;
  final List<List<models.Document>> inspectionsParCanalisation;

  const BzVisionReseauScreen({
    super.key,
    required this.chantierDoc,
    required this.canalisations,
    required this.inspectionsParCanalisation,
  });

  @override
  State<BzVisionReseauScreen> createState() => _BzVisionReseauScreenState();
}

class _BzVisionReseauScreenState extends State<BzVisionReseauScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _animCtrl;
  double _rotX  = 0.25;
  double _rotY  = 0.0;
  double _scale = 1.0;
  Offset? _lastPan;
  int? _selectedTroncon;
  String? _selectedNoeudId;

  // Réseau calculé
  List<_Troncon> _troncons = [];
  List<_Noeud>   _noeuds   = [];

  // Données nœuds depuis Appwrite
  final _service  = BzVisionService();
  // noeudId → document Appwrite
  Map<String, models.Document> _noeudDocs = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 12))..repeat();
    _initReseau();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  /// Charge les nœuds Appwrite puis construit le réseau avec angles.
  Future<void> _initReseau() async {
    final docs = await _service.getNoeuds(widget.chantierDoc.$id);
    final noeudDocsMap = <String, models.Document>{
      for (final d in docs) d.data['noeudId'] as String: d
    };
    if (mounted) setState(() => _noeudDocs = noeudDocsMap);
    _buildReseau(noeudDocsMap);
  }

  Future<void> _loadNoeudDocs() async {
    final docs = await _service.getNoeuds(widget.chantierDoc.$id);
    if (mounted) {
      final map = <String, models.Document>{
        for (final d in docs) d.data['noeudId'] as String: d
      };
      setState(() => _noeudDocs = map);
      _buildReseau(map);
    }
  }

  Future<void> _openNoeudPopup(String noeudId) async {
    setState(() => _selectedNoeudId = noeudId);
    final existing = _noeudDocs[noeudId];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NoeudSheet(
        noeudId:   noeudId,
        existing:  existing,
        onSave: (typeRacc, direction, angle, codeNF, obs) async {
          await _service.upsertNoeud(
            chantierId:       widget.chantierDoc.$id,
            noeudId:          noeudId,
            typeRaccordement: typeRacc,
            direction:        direction,
            angle:            angle,
            codeNF:           codeNF,
            observation:      obs,
          );
          await _loadNoeudDocs();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nœud enregistré ✓'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating));
        },
        onDelete: existing != null ? () async {
          await _service.deleteNoeud(existing.$id);
          await _loadNoeudDocs();
        } : null,
      ),
    );
    setState(() => _selectedNoeudId = null);
  }

  // ── Construction du graphe réseau ─────────────────
  void _buildReseau(Map<String, models.Document> noeudDocsMap) {
    final Map<String, _Noeud> noeudMap = {};

    // 1. Collecter tous les nœuds uniques
    for (int i = 0; i < widget.canalisations.length; i++) {
      final d     = widget.canalisations[i].data;
      final amont = (d['noeudAmont'] as String? ?? '').trim();
      final aval  = (d['noeudAval']  as String? ?? '').trim();
      final pA    = double.tryParse(d['profondeurAmont'] as String? ?? '') ?? 0;
      final pV    = double.tryParse(d['profondeurAval']  as String? ?? '') ?? 0;
      if (amont.isNotEmpty && !noeudMap.containsKey(amont)) {
        noeudMap[amont] = _Noeud(id: amont, profondeur: pA);
      }
      if (aval.isNotEmpty && !noeudMap.containsKey(aval)) {
        noeudMap[aval] = _Noeud(id: aval, profondeur: pV);
      }
    }

    // 2. Trouver le nœud source
    final avalCount = <String, int>{};
    for (final d in widget.canalisations) {
      final v = (d.data['noeudAval'] as String? ?? '').trim();
      avalCount[v] = (avalCount[v] ?? 0) + 1;
    }
    String startId = noeudMap.keys.first;
    for (final id in noeudMap.keys) {
      if ((avalCount[id] ?? 0) == 0) { startId = id; break; }
    }

    // 3. Positionnement directionnel — propagation depuis la source
    // Chaque nœud hérite de la direction du tronçon entrant + angle du nœud
    // Direction initiale : droite (angle = 0)
    final noeudDir   = <String, double>{}; // noeudId → direction courante (rad)
    final noeudPos   = <String, Offset>{}; // noeudId → position 2D (x, z)
    final visited    = <String>{};
    final queue      = <String>[startId];
    const stepSize   = 1.0; // unité de longueur normalisée

    noeudDir[startId] = 0.0; // part vers la droite
    noeudPos[startId] = Offset.zero;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      final currentDir = noeudDir[current] ?? 0.0;
      final currentPos = noeudPos[current] ?? Offset.zero;

      // Chercher tous les tronçons partant de ce nœud
      int branchIndex = 0;
      for (final canal in widget.canalisations) {
        final a = (canal.data['noeudAmont'] as String? ?? '').trim();
        final v = (canal.data['noeudAval']  as String? ?? '').trim();
        if (a != current || v.isEmpty || visited.contains(v)) continue;

        // La direction est définie sur le nœud AVAL —
        // c'est le nœud d'arrivée qui indique où repart le réseau
        final noeudDoc = noeudDocsMap[v];
        double newDir = currentDir;
        if (noeudDoc != null) {
          final direction = noeudDoc.data['direction'] as String? ?? '';
          final type      = noeudDoc.data['typeRaccordement'] as String? ?? '';
          final angle     = double.tryParse(
            noeudDoc.data['angle'] as String? ?? '') ?? 0;
          final angleRad  = angle * math.pi / 180;

          // Base de direction + angle de déviation
          if (direction == 'Droite') {
            newDir = 0 + angleRad;           // 0° + déviation
          } else if (direction == 'Bas') {
            newDir = math.pi / 2 + angleRad; // 90° + déviation
          } else if (direction == 'Gauche') {
            newDir = math.pi + angleRad;      // 180° + déviation
          } else if (direction == 'Haut') {
            newDir = -math.pi / 2 + angleRad;// -90° + déviation
          } else if (direction.isNotEmpty) {
            final deg = double.tryParse(direction) ?? 0;
            newDir = deg * math.pi / 180 + angleRad;
          } else if (type == 'Coude' && angle != 0) {
            newDir = currentDir + angleRad *
              (branchIndex % 2 == 0 ? 1 : -1);
          } else if (type == 'Té' || type == 'Confluence') {
            newDir = currentDir + (branchIndex == 0
              ? 0
              : math.pi / 2 * (branchIndex % 2 == 0 ? 1 : -1));
          }
        }
        // Longueur normalisée du tronçon
        final lon = double.tryParse(canal.data['longueur'] as String? ?? '') ?? 10;
        final normLen = (lon / 20).clamp(0.5, 3.0); // normaliser entre 0.5 et 3

        final newPos = Offset(
          currentPos.dx + math.cos(newDir) * normLen,
          currentPos.dy + math.sin(newDir) * normLen,
        );

        noeudDir[v] = newDir;
        noeudPos[v] = newPos;
        queue.add(v);
        branchIndex++;
      }
    }

    // 4. Appliquer les positions calculées aux nœuds
    for (final id in noeudMap.keys) {
      final pos = noeudPos[id] ?? Offset.zero;
      noeudMap[id]!.x = pos.dx;
      noeudMap[id]!.z = pos.dy; // z = profondeur latérale dans la vue
    }

    // 5. Construire les tronçons
    final troncons = <_Troncon>[];
    for (int i = 0; i < widget.canalisations.length; i++) {
      final doc   = widget.canalisations[i];
      final d     = doc.data;
      final amont = (d['noeudAmont'] as String? ?? '').trim();
      final aval  = (d['noeudAval']  as String? ?? '').trim();
      final nA    = noeudMap[amont];
      final nV    = noeudMap[aval];
      if (nA == null || nV == null) continue;

      final statut = d['statut'] as String? ?? 'a_inspecter';
      final lon    = double.tryParse(d['longueur'] as String? ?? '') ?? 10;
      final dia    = double.tryParse(d['diametre'] as String? ?? '') ?? 300;
      final ins    = i < widget.inspectionsParCanalisation.length
        ? widget.inspectionsParCanalisation[i] : <models.Document>[];

      int nbAnomalies = 0;
      final anomalies = <_Anomalie3D>[];
      for (final insp in ins) {
        final obs   = insp.data['observations'] as String? ?? '';
        final parts = obs.split('__CAPTURES__');
        final text  = parts[0];
        final lines = text.split('\n')
          .where((l) => l.trim().isNotEmpty).toList();
        for (int j = 0; j < lines.length; j++) {
          final lp   = lines[j].split('] ');
          final meta = lp.isNotEmpty ? lp[0].replaceAll('[', '') : '';
          final body = lp.length > 1 ? lp[1] : lines[j];
          double dist = 0;
          final dm = RegExp(r'(\d+(?:\.\d+)?)m').firstMatch(meta);
          if (dm != null) dist = double.tryParse(dm.group(1)!) ?? 0;
          String code = '';
          final cm = RegExp(r'^\[([A-Z]{3})\]').firstMatch(body);
          if (cm != null) code = cm.group(1)!;
          anomalies.add(_Anomalie3D(
            index: j, obs: body, dist: dist, code: code,
            ratio: lon > 0 ? (dist / lon).clamp(0.0, 1.0) : 0.5));
          nbAnomalies++;
        }
      }

      troncons.add(_Troncon(
        index:       i,
        doc:         doc,
        nom:         d['nom'] as String? ?? 'T-${i+1}',
        noeudAmont:  nA,
        noeudAval:   nV,
        longueur:    lon,
        diametre:    dia,
        statut:      statut,
        nbAnomalies: nbAnomalies,
        anomalies:   anomalies,
      ));
    }

    if (mounted) setState(() {
      _noeuds   = noeudMap.values.toList();
      _troncons = troncons;
    });
  }

  // ── Couleur par statut ─────────────────────────────
  Color _couleurStatut(String statut, int nbAno) {
    if (nbAno > 0 && statut == 'inspecte') return Colors.orange;
    switch (statut) {
      case 'inspecte':  return const Color(0xFF22C55E);
      case 'en_cours':  return const Color(0xFF22D3EE);
      default:          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch  = widget.chantierDoc.data;
    final nom = ch['nom'] as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          const Icon(Icons.account_tree_outlined,
            color: Color(0xFF22D3EE), size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RÉSEAU 3D',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
            Text(nom, style: TextStyle(
              color: Colors.grey[500], fontSize: 10)),
          ]),
        ]),
        actions: const [],
      ),
      body: Column(children: [
        // ── Légende ───────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: Colors.black.withOpacity(0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            _dot(Colors.grey,               'À inspecter'),
            const SizedBox(width: 14),
            _dot(const Color(0xFF22D3EE),   'En cours'),
            const SizedBox(width: 14),
            _dot(const Color(0xFF22C55E),   'Inspecté'),
            const SizedBox(width: 14),
            _dot(Colors.orange,             'Anomalies'),
          ])),
        // ── Zone 3D ───────────────────────────────
        Expanded(
          child: Stack(children: [
          GestureDetector(
            onScaleStart: (d) => _lastPan = d.localFocalPoint,
            onScaleUpdate: (d) {
              if (_lastPan != null) {
                final delta = d.localFocalPoint - _lastPan!;
                setState(() {
                  _rotY += delta.dx * 0.008;
                  _rotX  = (_rotX + delta.dy * 0.008).clamp(-0.9, 0.9);
                  if (d.scale != 1.0) {
                    _scale = (_scale * d.scale).clamp(0.4, 3.0);
                  }
                });
              }
              _lastPan = d.localFocalPoint;
            },
            onScaleEnd: (_) => _lastPan = null,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, __) => CustomPaint(
                painter: _ReseauPainter(
                  troncons:    _troncons,
                  noeuds:      _noeuds,
                  rotX:        _rotX,
                  rotY:        _rotY,
                  scale:       _scale,
                  selected:    _selectedTroncon,
                  selectedNoeud: _selectedNoeudId,
                  animValue:   _animCtrl.value,
                  noeudDocs:   _noeudDocs,
                  getColor:    _couleurStatut,
                  onTapTroncon: (i) => setState(() =>
                    _selectedTroncon = _selectedTroncon == i ? null : i),
                  onTapNoeud:  (id) => _openNoeudPopup(id),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          // ── Boutons zoom ───────────────────────────
          Positioned(
            right: 12, bottom: 12,
            child: Column(children: [
              _zoomBtn(Icons.add, () => setState(() =>
                _scale = (_scale * 1.25).clamp(0.4, 3.0))),
              const SizedBox(height: 6),
              // Indicateur zoom
              Container(
                width: 36, height: 24,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1))),
                child: Center(child: Text(
                  '${(_scale * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white60, fontSize: 8,
                    fontWeight: FontWeight.w700)))),
              const SizedBox(height: 6),
              _zoomBtn(Icons.remove, () => setState(() =>
                _scale = (_scale * 0.8).clamp(0.4, 3.0))),
              const SizedBox(height: 10),
              // Bouton reset vue
              _zoomBtn(Icons.center_focus_strong_outlined, () => setState(() {
                _scale = 1.0;
                _rotX  = 0.25;
                _rotY  = 0.0;
              }), color: const Color(0xFF22D3EE)),
            ])),
          ])),

        // ── Popup tronçon sélectionné ──────────────
        if (_selectedTroncon != null &&
            _selectedTroncon! < _troncons.length)
          _buildTronconPopup(_troncons[_selectedTroncon!]),

        // ── Barre infos ───────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black.withOpacity(0.7),
          child: Row(children: [
            Text('${_troncons.length} tronçon(s)',
              style: const TextStyle(color: Color(0xFF22D3EE),
                fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(width: 16),
            Text('${_noeuds.length} nœud(s)',
              style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            const Spacer(),
            Icon(Icons.touch_app, color: Colors.grey[600], size: 12),
            const SizedBox(width: 4),
            Text('Glisser / pincer / tap tronçon',
              style: TextStyle(color: Colors.grey[600], fontSize: 9)),
          ])),

        // ── Liste tronçons scrollable ──────────────
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _troncons.length,
            itemBuilder: (_, i) {
              final t         = _troncons[i];
              final isSelected= _selectedTroncon == i;
              final color     = _couleurStatut(t.statut, t.nbAnomalies);
              return GestureDetector(
                onTap: () => setState(() =>
                  _selectedTroncon = isSelected ? null : i),
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                      ? color.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                        ? color.withOpacity(0.6)
                        : Colors.white.withOpacity(0.08))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(children: [
                      Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Expanded(child: Text(t.nom,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 10, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 3),
                    Text('${t.noeudAmont.id} → ${t.noeudAval.id}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 8),
                      overflow: TextOverflow.ellipsis),
                    Text('DN${t.diametre.toStringAsFixed(0)} · ${t.longueur.toStringAsFixed(0)}m'
                      '${t.nbAnomalies > 0 ? " · ⚠ ${t.nbAnomalies}" : ""}',
                      style: TextStyle(
                        color: t.nbAnomalies > 0 ? Colors.orange : Colors.grey[700],
                        fontSize: 8)),
                  ])));
            },
          )),
        ]),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap,
      {Color color = Colors.white}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.3), blurRadius: 6)]),
        child: Icon(icon, color: color, size: 18)));

  Widget _dot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
    Container(width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 3),
    Text(label, style: TextStyle(
      color: Colors.grey[500], fontSize: 8)),
  ]);

  Widget _buildTronconPopup(_Troncon t) {
    final color = _couleurStatut(t.statut, t.nbAnomalies);
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.15), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(t.nom,
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 13))),
          GestureDetector(
            onTap: () => setState(() => _selectedTroncon = null),
            child: const Icon(Icons.close, color: Colors.grey, size: 16)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 16, children: [
          _infoChip('${t.noeudAmont.id} → ${t.noeudAval.id}',
            Icons.compare_arrows),
          _infoChip('DN ${t.diametre.toStringAsFixed(0)} mm',
            Icons.circle_outlined),
          _infoChip('${t.longueur.toStringAsFixed(1)} m',
            Icons.straighten),
          if (t.nbAnomalies > 0)
            _infoChip('${t.nbAnomalies} anomalie(s)', Icons.warning_amber,
              color: Colors.orange),
        ]),
        // Anomalies du tronçon
        if (t.anomalies.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: t.anomalies.length,
              itemBuilder: (_, i) {
                final a = t.anomalies[i];
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (a.code.isNotEmpty) ...[
                      Text(a.code, style: const TextStyle(
                        color: Color(0xFF22D3EE),
                        fontSize: 9, fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
                      const SizedBox(width: 4),
                    ],
                    Text('${a.dist.toStringAsFixed(1)}m',
                      style: const TextStyle(
                        color: Colors.orange, fontSize: 9)),
                  ]));
              }),
          ),
        ],
      ]),
    );
  }

  Widget _infoChip(String label, IconData icon,
      {Color color = const Color(0xFF22D3EE)}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 10),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 9)),
    ]);
}

// ── Painter réseau 2.5D ──────────────────────────────────────────────────────
class _ReseauPainter extends CustomPainter {
  final List<_Troncon> troncons;
  final List<_Noeud>   noeuds;
  final double rotX, rotY, scale, animValue;
  final int?   selected;
  final String? selectedNoeud;
  final Map<String, models.Document> noeudDocs;
  final Color  Function(String statut, int nbAno) getColor;
  final Function(int)    onTapTroncon;
  final Function(String) onTapNoeud;

  final List<Rect>             _tronconRects = [];
  final Map<String, Offset>    _noeudPositions = {};

  _ReseauPainter({
    required this.troncons, required this.noeuds,
    required this.rotX, required this.rotY, required this.scale,
    required this.selected, required this.selectedNoeud,
    required this.animValue, required this.noeudDocs,
    required this.getColor,
    required this.onTapTroncon, required this.onTapNoeud,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;

    // Fond étoilé
    canvas.drawRect(Offset.zero & size,
      Paint()..color = const Color(0xFF020208));
    final rng = math.Random(99);
    final starP = Paint()..color = Colors.white.withOpacity(0.25);
    for (int i = 0; i < 60; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        0.7, starP);
    }

    if (troncons.isEmpty) {
      // Message vide
      final tp = TextPainter(
        text: const TextSpan(text: 'Aucun tronçon avec nœuds renseignés',
          style: TextStyle(color: Colors.grey, fontSize: 13)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(cx - tp.width/2, cy - tp.height/2));
      return;
    }

    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);
    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);

    // Normalisation des coordonnées
    final allX = noeuds.map((n) => n.x).toList();
    final allZ = noeuds.map((n) => n.z).toList();
    final allP = noeuds.map((n) => n.profondeur).toList();
    final minX = allX.reduce(math.min);
    final maxX = allX.reduce(math.max);
    final minZ = allZ.reduce(math.min);
    final maxZ = allZ.reduce(math.max);
    final minP = allP.isNotEmpty ? allP.reduce(math.min) : 0.0;
    final maxP = allP.isNotEmpty ? allP.reduce(math.max) : 5.0;
    final rangeX = (maxX - minX).clamp(1.0, double.infinity);
    final rangeZ = (maxZ - minZ).clamp(1.0, double.infinity);
    final rangeP = (maxP - minP).clamp(0.5, double.infinity);

    final span  = size.width * 0.38 * scale;
    final spanZ = size.height * 0.18 * scale;
    final spanP = size.height * 0.40 * scale; // profondeur → axe Y (amplifié)

    // Projeter un nœud
    // Convention : profondeur croissante = descend vers le bas (axe Y positif)
    Offset projectNoeud(_Noeud n) {
      final nx = (n.x - (minX + maxX) / 2) / rangeX * span * 2;
      // Inversion : profondeur max (le plus bas dans le sol) → valeur Y positive (bas écran)
      final ny = (n.profondeur - (minP + maxP) / 2) / rangeP * spanP;
      final nz = (n.z - (minZ + maxZ) / 2) / rangeZ * spanZ * 2;
      final rx  = nx;
      final ry  = ny * cosX - nz * sinX;  // ny positif = descend
      final rz  = ny * sinX + nz * cosX;
      final rx2 = rx * cosY + rz * sinY;
      final rz2 = -rx * sinY + rz * cosY;
      final s   = 600 / (600 + rz2 * 0.5);
      return Offset(cx + rx2 * s, cy + ry * s);
    }

    _tronconRects.clear();

    // ── Dessin des tronçons — double paroi ────────
    for (int i = 0; i < troncons.length; i++) {
      final t      = troncons[i];
      final pA     = projectNoeud(t.noeudAmont);
      final pV     = projectNoeud(t.noeudAval);
      final color  = getColor(t.statut, t.nbAnomalies);
      final isSel  = selected == i;
      // Épaisseur proportionnelle au DN
      final outer  = (t.diametre / 120).clamp(5.0, 22.0) * scale;
      final inner  = outer * 0.62;
      final wall   = (outer - inner) / 2;

      final dir    = pV - pA;
      final len    = dir.distance;
      if (len < 1) continue;
      final perp   = Offset(-dir.dy, dir.dx) / len;

      // ── Ombre portée ──
      canvas.drawLine(pA + const Offset(2, 3), pV + const Offset(2, 3),
        Paint()
          ..color = Colors.black.withOpacity(0.35)
          ..strokeWidth = outer + 2
          ..strokeCap = StrokeCap.round);

      // ── Paroi extérieure ──
      final wallColor = isSel
        ? Colors.white.withOpacity(0.9)
        : color.withOpacity(0.75);
      canvas.drawLine(pA, pV,
        Paint()
          ..color = wallColor
          ..strokeWidth = outer
          ..strokeCap = StrokeCap.round);

      // ── Intérieur du tuyau (plus sombre) ──
      final innerColor = isSel
        ? const Color(0xFF334155)
        : Color.lerp(color, Colors.black, 0.6)!.withOpacity(0.9);
      canvas.drawLine(pA, pV,
        Paint()
          ..color = innerColor
          ..strokeWidth = inner
          ..strokeCap = StrokeCap.round);

      // ── Reflet haut (ligne lumineuse) ──
      final highlightOff = perp * (inner * 0.35);
      canvas.drawLine(pA + highlightOff, pV + highlightOff,
        Paint()
          ..color = Colors.white.withOpacity(isSel ? 0.5 : 0.2)
          ..strokeWidth = (wall * 0.6).clamp(0.5, 2.5)
          ..strokeCap = StrokeCap.round);

      // ── Ombre bas (ligne sombre) ──
      canvas.drawLine(pA - highlightOff, pV - highlightOff,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..strokeWidth = (wall * 0.4).clamp(0.3, 1.5)
          ..strokeCap = StrokeCap.round);

      // ── Bandes de soudure (joints) ──
      if (scale > 0.6 && len > 30) {
        final jointCount = math.max(1, (len / 60).floor());
        for (int j = 1; j <= jointCount; j++) {
          final ratio = j / (jointCount + 1);
          final jp    = pA + dir * ratio;
          final jPerp = perp * (outer / 2);
          canvas.drawLine(jp - jPerp, jp + jPerp,
            Paint()
              ..color = Colors.black.withOpacity(0.25)
              ..strokeWidth = 1.5 * scale
              ..strokeCap = StrokeCap.butt);
        }
      }

      // ── Label tronçon ──
      final mid = Offset((pA.dx + pV.dx) / 2, (pA.dy + pV.dy) / 2);
      _tronconRects.add(Rect.fromCenter(center: mid, width: 80, height: 30));

      // Badge DN
      if (scale > 0.6) {
        final dnStr = 'DN${t.diametre.toStringAsFixed(0)}';
        final dnTp  = TextPainter(
          text: TextSpan(text: dnStr,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: (7 * scale).clamp(5.0, 9.0),
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
          textDirection: TextDirection.ltr)..layout();
        dnTp.paint(canvas, mid - Offset(dnTp.width / 2, dnTp.height / 2));
      }

      // Nom tronçon au-dessus
      if (isSel || scale > 0.8) {
        final tp = TextPainter(
          text: TextSpan(text: t.nom,
            style: TextStyle(
              color: isSel ? Colors.white : color,
              fontSize: (9 * scale).clamp(7.0, 13.0),
              fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
              shadows: const [Shadow(color: Colors.black, blurRadius: 5)])),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas,
          mid - Offset(tp.width / 2, outer / 2 + tp.height + 3));
      }

      // ── Anomalies sur le tronçon ──
      for (final a in t.anomalies) {
        final ax    = pA + (pV - pA) * a.ratio;
        final pulse = math.sin(animValue * 2 * math.pi + i) * 0.5 + 0.5;
        // Halo pulsant
        canvas.drawCircle(ax, (outer / 2 + 4 + pulse * 3),
          Paint()
            ..color = Colors.orange.withOpacity(0.25 + pulse * 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        // Marqueur triangulaire
        final triSize = (4 + pulse) * scale;
        final path    = Path()
          ..moveTo(ax.dx, ax.dy - outer / 2 - triSize - 2)
          ..lineTo(ax.dx - triSize, ax.dy - outer / 2 - 2)
          ..lineTo(ax.dx + triSize, ax.dy - outer / 2 - 2)
          ..close();
        canvas.drawPath(path, Paint()..color = Colors.orange);
        if (a.code.isNotEmpty && scale > 0.6) {
          final tp = TextPainter(
            text: TextSpan(text: a.code,
              style: TextStyle(color: Colors.orange,
                fontSize: (7 * scale).clamp(5.0, 9.0),
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
            textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(
            ax.dx + triSize + 2,
            ax.dy - outer / 2 - triSize - tp.height / 2 - 2));
        }
      }
    }

    // ── Dessin des nœuds — regard de visite ───────
    for (final n in noeuds) {
      final p        = projectNoeud(n);
      final hasData  = noeudDocs.containsKey(n.id);
      final isSel    = selectedNoeud == n.id;
      final nColor   = hasData ? const Color(0xFFF97316) : const Color(0xFF94A3B8);
      final nSize    = (10.0 * scale).clamp(7.0, 16.0);

      _noeudPositions[n.id] = p;

      // Halo sélection
      if (isSel) {
        canvas.drawCircle(p, nSize + 8,
          Paint()
            ..color = const Color(0xFF22D3EE).withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      }

      // ── Regard de visite : carré arrondi ──
      final rRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: nSize * 1.8, height: nSize * 1.8),
        Radius.circular(nSize * 0.35));

      // Ombre
      canvas.drawRRect(rRect.shift(const Offset(1.5, 2)),
        Paint()..color = Colors.black.withOpacity(0.5));

      // Corps du regard
      canvas.drawRRect(rRect,
        Paint()..color = const Color(0xFF1E293B));
      canvas.drawRRect(rRect,
        Paint()
          ..color = nColor.withOpacity(isSel ? 1.0 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2.5 : 1.5);

      // Croix intérieure (tampon de regard)
      final cSize = nSize * 0.45;
      final cPaint = Paint()
        ..color = nColor.withOpacity(0.6)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(p + Offset(-cSize, 0), p + Offset(cSize, 0), cPaint);
      canvas.drawLine(p + Offset(0, -cSize), p + Offset(0, cSize), cPaint);

      // Badge type raccordement
      if (hasData) {
        final doc  = noeudDocs[n.id]!;
        final type = doc.data['typeRaccordement'] as String? ?? '';
        final bp   = p + Offset(nSize, -nSize * 0.9);
        canvas.drawCircle(bp, nSize * 0.55,
          Paint()..color = const Color(0xFFF97316));
        if (type.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: type.substring(0, math.min(1, type.length)),
              style: TextStyle(color: Colors.white,
                fontSize: (6 * scale).clamp(4.0, 8.0),
                fontWeight: FontWeight.w900)),
            textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, bp - Offset(tp.width / 2, tp.height / 2));
        }
      }

      // Label nœud
      if (scale > 0.5) {
        final tp = TextPainter(
          text: TextSpan(text: n.id,
            style: TextStyle(
              color: isSel ? Colors.white : Colors.white60,
              fontSize: (8 * scale).clamp(6.0, 11.0),
              fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas,
          p + Offset(-tp.width / 2, nSize + 2));
      }

      // Profondeur radier
      if (n.profondeur > 0 && scale > 0.7) {
        final tp = TextPainter(
          text: TextSpan(text: '▼ ${n.profondeur.toStringAsFixed(2)}m',
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: (7 * scale).clamp(5.0, 9.0),
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas,
          p + Offset(-tp.width / 2, -nSize * 1.1 - tp.height - 1));
      }
    }

    // ── Sol (grille perspective) ──────────────────
    _drawGround(canvas, size, cx, cy, cosX, sinX, cosY, sinY, scale);
  }


  void _drawGround(Canvas canvas, Size size,
      double cx, double cy,
      double cosX, double sinX,
      double cosY, double sinY, double sc) {
    const gSize = 300.0;
    const gStep = 50.0;

    Offset proj(double x, double y, double z) {
      final ry  = y * cosX - z * sinX;
      final rz  = y * sinX + z * cosX;
      final rx2 = x * cosY + rz * sinY;
      final rz2 = -x * sinY + rz * cosY;
      final s   = 600 / (600 + rz2 * 0.5);
      return Offset(cx + rx2 * s * sc, cy + ry * s * sc);
    }

    // ── Remplissage sol semi-transparent ──────────
    final corners = [
      proj(-gSize, 0, -gSize), proj(gSize, 0, -gSize),
      proj(gSize,  0,  gSize), proj(-gSize, 0,  gSize),
    ];
    final fillPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(fillPath,
      Paint()..color = const Color(0xFF0F172A).withOpacity(0.5));

    // ── Grille principale ──────────────────────────
    for (double x = -gSize; x <= gSize; x += gStep) {
      canvas.drawLine(proj(x, 0, -gSize), proj(x, 0, gSize),
        Paint()
          ..color = const Color(0xFF22D3EE).withOpacity(0.18)
          ..strokeWidth = 0.8);
    }
    for (double z = -gSize; z <= gSize; z += gStep) {
      canvas.drawLine(proj(-gSize, 0, z), proj(gSize, 0, z),
        Paint()
          ..color = const Color(0xFF22D3EE).withOpacity(0.18)
          ..strokeWidth = 0.8);
    }

    // ── Grille secondaire (mailles fines) ─────────
    const gStep2 = 25.0;
    for (double x = -gSize; x <= gSize; x += gStep2) {
      if (x % gStep == 0) continue;
      canvas.drawLine(proj(x, 0, -gSize), proj(x, 0, gSize),
        Paint()
          ..color = const Color(0xFF22D3EE).withOpacity(0.06)
          ..strokeWidth = 0.4);
    }
    for (double z = -gSize; z <= gSize; z += gStep2) {
      if (z % gStep == 0) continue;
      canvas.drawLine(proj(-gSize, 0, z), proj(gSize, 0, z),
        Paint()
          ..color = const Color(0xFF22D3EE).withOpacity(0.06)
          ..strokeWidth = 0.4);
    }

    // ── Bordure avant du sol (ligne épaisse) ──────
    canvas.drawLine(
      proj(-gSize, 0, gSize), proj(gSize, 0, gSize),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.5)
        ..strokeWidth = 1.5);

    // ── Bordures latérales ─────────────────────────
    canvas.drawLine(
      proj(-gSize, 0, -gSize), proj(-gSize, 0, gSize),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.25)
        ..strokeWidth = 1.0);
    canvas.drawLine(
      proj(gSize, 0, -gSize), proj(gSize, 0, gSize),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.25)
        ..strokeWidth = 1.0);

    // ── Axes X et Z au sol ─────────────────────────
    canvas.drawLine(proj(-gSize, 0, 0), proj(gSize, 0, 0),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.35)
        ..strokeWidth = 1.2);
    canvas.drawLine(proj(0, 0, -gSize), proj(0, 0, gSize),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.35)
        ..strokeWidth = 1.2);

    // ── Label "SOL" ───────────────────────────────
    final solPos = proj(gSize + 10, 0, gSize);
    final tp = TextPainter(
      text: const TextSpan(text: 'SOL',
        style: TextStyle(color: Color(0xFF22D3EE),
          fontSize: 9, fontWeight: FontWeight.w700,
          letterSpacing: 1.5)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, solPos);

    // ── Axe Z vertical (profondeur) ───────────────
    canvas.drawLine(
      proj(-gSize, -60 * sc, gSize),
      proj(-gSize,  60 * sc, gSize),
      Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..strokeWidth = 1.0);

    // Tirets profondeur
    for (int m = -3; m <= 3; m++) {
      if (m == 0) continue;
      final yVal = m * 20.0 * sc;
      final p1   = proj(-gSize - 8, yVal / sc, gSize);
      final p2   = proj(-gSize + 8, yVal / sc, gSize);
      canvas.drawLine(p1, p2,
        Paint()
          ..color = Colors.white.withOpacity(0.2)
          ..strokeWidth = 0.8);
    }
  }

  @override
  bool hitTest(Offset position) {
    // Nœuds en priorité (plus petits, plus précis)
    for (final entry in _noeudPositions.entries) {
      if ((position - entry.value).distance < 20) {
        onTapNoeud(entry.key);
        return true;
      }
    }
    // Tronçons
    for (int i = 0; i < _tronconRects.length; i++) {
      if (_tronconRects[i].inflate(20).contains(position)) {
        onTapTroncon(i);
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(_ReseauPainter old) => true;
}

// Extension utilitaire
extension _OffsetNorm on Offset {
  Offset normalize() {
    final d = distance;
    return d == 0 ? Offset.zero : Offset(dx / d, dy / d);
  }
}

// ── Modèles ──────────────────────────────────────────────────────────────────
class _Noeud {
  final String id;
  final double profondeur;
  double x = 0, z = 0;
  _Noeud({required this.id, required this.profondeur});
}

class _Anomalie3D {
  final int    index;
  final String obs, code;
  final double dist, ratio;
  const _Anomalie3D({required this.index, required this.obs,
    required this.code, required this.dist, required this.ratio});
}

class _Troncon {
  final int           index;
  final models.Document doc;
  final String        nom, statut;
  final _Noeud        noeudAmont, noeudAval;
  final double        longueur, diametre;
  final int           nbAnomalies;
  final List<_Anomalie3D> anomalies;

  const _Troncon({
    required this.index, required this.doc, required this.nom,
    required this.noeudAmont, required this.noeudAval,
    required this.longueur, required this.diametre,
    required this.statut, required this.nbAnomalies,
    required this.anomalies,
  });
}


// ── Popup édition nœud ───────────────────────────────────────────────────────
class _NoeudSheet extends StatefulWidget {
  final String noeudId;
  final models.Document? existing;
  final Future<void> Function(String type, String direction,
      String angle, String codeNF, String obs) onSave;
  final VoidCallback? onDelete;

  const _NoeudSheet({
    required this.noeudId, required this.existing,
    required this.onSave, this.onDelete,
  });
  @override
  State<_NoeudSheet> createState() => _NoeudSheetState();
}

class _NoeudSheetState extends State<_NoeudSheet> {
  late String _typeRacc;
  late String _codeNF;
  late String _direction;
  late final TextEditingController _angleCtrl;
  late final TextEditingController _obsCtrl;
  bool _saving = false;

  static const _types = [
    'Direct', 'Coude', 'Té', 'Confluence', 'Siphon',
    'Déversoir', 'Regard de visite', 'Autre',
  ];
  static const _codes = [
    '', 'BAJ C', 'BCA', 'BAA', 'BCC', 'DAC', 'PAD', 'Autre',
  ];

  @override
  void initState() {
    super.initState();
    final d    = widget.existing?.data;
    _typeRacc  = d?['typeRaccordement'] as String? ?? 'Direct';
    _codeNF    = d?['codeNF']          as String? ?? '';
    _direction = d?['direction']        as String? ?? 'Droite';
    _angleCtrl = TextEditingController(text: d?['angle']       as String? ?? '');
    _obsCtrl   = TextEditingController(text: d?['observation'] as String? ?? '');
    if (!_types.contains(_typeRacc)) _typeRacc = 'Direct';
    if (!_codes.contains(_codeNF))   _codeNF   = '';
    const dirs = ['Droite', 'Bas', 'Gauche', 'Haut'];
    if (!dirs.contains(_direction)) _direction = 'Droite';
  }

  @override
  void dispose() {
    _angleCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFF97316).withOpacity(0.4))),
              child: Text('NŒUD ${widget.noeudId}',
                style: const TextStyle(color: Color(0xFFF97316),
                  fontSize: 10, fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'))),
            const SizedBox(width: 10),
            const Text('Raccordement',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            if (widget.onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline,
                  color: Colors.red[400], size: 18),
                onPressed: () {
                  widget.onDelete!();
                  Navigator.pop(context);
                }),
          ]),
          const SizedBox(height: 16),

          // Type de raccordement
          _label('Type de raccordement'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _typeRacc, isExpanded: true,
                dropdownColor: const Color(0xFF0D0D0D),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.expand_more,
                  color: Color(0xFF22D3EE), size: 18),
                items: _types.map((t) => DropdownMenuItem(
                  value: t, child: Text(t,
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 13)))).toList(),
                onChanged: (v) => setState(
                  () => _typeRacc = v ?? 'Direct')))),
          const SizedBox(height: 14),

          // Direction de sortie
          _label('Direction de sortie du tronçon aval'),
          Row(children: [
            _dirBtn('Droite', Icons.arrow_forward),
            const SizedBox(width: 6),
            _dirBtn('Bas',    Icons.arrow_downward),
            const SizedBox(width: 6),
            _dirBtn('Gauche', Icons.arrow_back),
            const SizedBox(width: 6),
            _dirBtn('Haut',   Icons.arrow_upward),
          ]),
          const SizedBox(height: 10),
          _label('Angle de déviation (°) *'),
          _textField(_angleCtrl, 'Ex: 0 (droit), 45 (oblique), 90 (équerre)',
            Icons.rotate_90_degrees_ccw_outlined,
            keyboard: TextInputType.number),
          const SizedBox(height: 14),

          // Code NF EN 13508-2
          _label('Code NF EN 13508-2'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _codeNF, isExpanded: true,
                dropdownColor: const Color(0xFF0D0D0D),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.expand_more,
                  color: Color(0xFF22D3EE), size: 18),
                items: _codes.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c.isEmpty ? '— Aucun —' : c,
                    style: TextStyle(
                      color: c.isEmpty
                        ? Colors.grey[600] : Colors.white70,
                      fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _codeNF = v ?? '')))),
          const SizedBox(height: 14),

          // Observation
          _label('Observation libre'),
          _textField(_obsCtrl,
            'Remarque sur ce nœud de raccordement...', Icons.notes),
          const SizedBox(height: 20),

          // Bouton sauvegarder
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                await widget.onSave(
                  _typeRacc, _direction,
                  _angleCtrl.text.trim(),
                  _codeNF, _obsCtrl.text.trim());
                if (mounted) Navigator.pop(context);
              },
              icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Enregistrement...' : 'Enregistrer',
                style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))))),
        ])));
  }

  Widget _dirBtn(String label, IconData icon) {
    final isSel = _direction == label;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _direction = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSel
            ? const Color(0xFF22D3EE).withOpacity(0.15)
            : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel
              ? const Color(0xFF22D3EE)
              : Colors.white.withOpacity(0.08))),
        child: Column(children: [
          Icon(icon,
            color: isSel ? const Color(0xFF22D3EE) : Colors.grey[600],
            size: 18),
          const SizedBox(height: 3),
          Text(label,
            style: TextStyle(
              color: isSel ? const Color(0xFF22D3EE) : Colors.grey[600],
              fontSize: 9,
              fontWeight: isSel ? FontWeight.w900 : FontWeight.normal)),
        ]))));
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(
      color: Colors.grey[400], fontSize: 10,
      fontWeight: FontWeight.w700)));

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
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE), width: 1.5))));
}
