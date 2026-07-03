// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;

class BzVision3DScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final List<models.Document> inspections;
  const BzVision3DScreen({super.key,
    required this.canalisationDoc,
    required this.inspections});
  @override
  State<BzVision3DScreen> createState() => _BzVision3DScreenState();
}

class _BzVision3DScreenState extends State<BzVision3DScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  double _rotX = 0.3;
  double _rotY = 0.0;
  Offset? _lastPan;
  int? _selectedAnomalie;

  // Anomalies parsées depuis les inspections
  List<_Anomalie> _anomalies = [];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this,
      duration: const Duration(seconds: 8))..repeat();
    _parseAnomalies();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  void _parseAnomalies() {
    final anomalies = <_Anomalie>[];
    for (final ins in widget.inspections) {
      final obs = ins.data['observations'] as String? ?? '';
      final lines = obs.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final parts = line.split('] ');
        final meta  = parts.isNotEmpty ? parts[0].replaceAll('[', '') : '';
        final text  = parts.length > 1 ? parts[1] : line;
        // Extraire la distance depuis meta "[mm:ss | Xm]"
        double dist = 0;
        final distMatch = RegExp(r'(\d+(?:\.\d+)?)m').firstMatch(meta);
        if (distMatch != null) dist = double.tryParse(distMatch.group(1)!) ?? 0;
        final timeMatch = RegExp(r'(\d+:\d+)').firstMatch(meta);
        final time = timeMatch?.group(1) ?? '';
        anomalies.add(_Anomalie(
          index: anomalies.length,
          obs:   text,
          dist:  dist,
          time:  time,
        ));
      }
    }
    setState(() => _anomalies = anomalies);
  }

  @override
  Widget build(BuildContext context) {
    final canal = widget.canalisationDoc.data;
    final nom   = canal['nom'] as String? ?? '';
    final dia   = canal['diametre'] as String? ?? '—';
    final lon   = canal['longueur'] as String? ?? '—';
    final lonVal = double.tryParse(
      lon.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 10.0;

    return Scaffold(
      backgroundColor: const Color(0xFF020208),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          const Icon(Icons.view_in_ar, color: Color(0xFF22D3EE), size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('VUE 3D — CANALISATION',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 1.5)),
            Text(nom, style: TextStyle(color: Colors.grey[500],
              fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        ]),
        actions: [
          // Légende
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              _legendDot(const Color(0xFF22D3EE), 'Tuyau'),
              const SizedBox(width: 10),
              _legendDot(Colors.red, 'Anomalie'),
              const SizedBox(width: 10),
              _legendDot(Colors.blue, 'Caméra'),
            ]),
          ),
        ],
      ),
      body: Column(children: [
        // ── Zone 3D interactive ──────────────────
        Expanded(
          child: GestureDetector(
            onPanStart: (d) => _lastPan = d.localPosition,
            onPanUpdate: (d) {
              if (_lastPan != null) {
                final delta = d.localPosition - _lastPan!;
                setState(() {
                  _rotY += delta.dx * 0.01;
                  _rotX = (_rotX + delta.dy * 0.01).clamp(-0.8, 0.8);
                });
              }
              _lastPan = d.localPosition;
            },
            onPanEnd: (_) => _lastPan = null,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, __) => CustomPaint(
                painter: _PipePainter(
                  rotX:       _rotX,
                  rotY:       _rotY + _animCtrl.value * 0.5,
                  anomalies:  _anomalies,
                  longueur:   lonVal,
                  selected:   _selectedAnomalie,
                  onTapAnomalie: (i) => setState(() =>
                    _selectedAnomalie = _selectedAnomalie == i ? null : i),
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),

        // ── Popup anomalie sélectionnée ──────────
        if (_selectedAnomalie != null &&
            _selectedAnomalie! < _anomalies.length)
          _buildAnomaliePopup(_anomalies[_selectedAnomalie!]),

        // ── Instructions + stats ─────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            border: Border(top: BorderSide(
              color: Colors.white.withOpacity(0.05)))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ø $dia • ${lonVal.toStringAsFixed(0)}m',
                style: const TextStyle(color: Color(0xFF22D3EE),
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
              Row(children: [
                Icon(Icons.touch_app, color: Colors.grey[600], size: 12),
                const SizedBox(width: 4),
                Text('Glisser pour pivoter • Tap sur une anomalie',
                  style: TextStyle(color: Colors.grey[600], fontSize: 9)),
              ]),
              Text('${_anomalies.length} anomalie${_anomalies.length > 1 ? "s" : ""}',
                style: const TextStyle(color: Colors.red, fontSize: 10,
                  fontWeight: FontWeight.w900)),
            ]),
        ),

        // ── Liste anomalies scrollable ────────────
        if (_anomalies.isNotEmpty)
          Container(
            height: 80,
            color: const Color(0xFF0A0A0F),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _anomalies.length,
              itemBuilder: (_, i) {
                final a = _anomalies[i];
                final isSelected = _selectedAnomalie == i;
                return GestureDetector(
                  onTap: () => setState(() =>
                    _selectedAnomalie = isSelected ? null : i),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                        ? Colors.red.withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                          ? Colors.red.withOpacity(0.5)
                          : Colors.white.withOpacity(0.08))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(children: [
                        Container(width: 16, height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                          child: Center(child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white,
                              fontSize: 8, fontWeight: FontWeight.w900)))),
                        const SizedBox(width: 6),
                        Text('${a.dist.toStringAsFixed(1)}m',
                          style: const TextStyle(color: Color(0xFF22D3EE),
                            fontSize: 9, fontWeight: FontWeight.w900)),
                        if (a.time.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text('t=${a.time}',
                            style: TextStyle(color: Colors.grey[600],
                              fontSize: 8, fontFamily: 'monospace')),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      Text(a.obs, style: TextStyle(color: Colors.grey[400],
                        fontSize: 9), maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: Colors.grey[500],
        fontSize: 8, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _buildAnomaliePopup(_Anomalie a) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
        boxShadow: [BoxShadow(
          color: Colors.red.withOpacity(0.2), blurRadius: 16)]),
      child: Row(children: [
        Container(width: 8, height: 40,
          decoration: BoxDecoration(color: Colors.red,
            borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Anomalie #${a.index + 1} — ${a.dist.toStringAsFixed(2)}m',
            style: const TextStyle(color: Colors.red,
              fontWeight: FontWeight.w900, fontSize: 11)),
          Text(a.obs, style: const TextStyle(color: Colors.white70,
            fontSize: 12, height: 1.4)),
          if (a.time.isNotEmpty)
            Text('t = ${a.time}',
              style: TextStyle(color: Colors.grey[600],
                fontSize: 9, fontFamily: 'monospace')),
        ])),
        GestureDetector(
          onTap: () => setState(() => _selectedAnomalie = null),
          child: const Icon(Icons.close, color: Colors.grey, size: 16)),
      ]),
    );
  }
}

// ── Modèle anomalie ──────────────────────────────
class _Anomalie {
  final int    index;
  final String obs, time;
  final double dist;
  const _Anomalie({required this.index, required this.obs,
    required this.time, required this.dist});
}

// ── Painter 3D tuyau ─────────────────────────────
class _PipePainter extends CustomPainter {
  final double rotX, rotY, longueur;
  final List<_Anomalie> anomalies;
  final int? selected;
  final Function(int) onTapAnomalie;

  _PipePainter({required this.rotX, required this.rotY,
    required this.anomalies, required this.longueur,
    required this.selected, required this.onTapAnomalie});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // ── Fond étoilé ──────────────────────────────
    final bgPaint = Paint()
      ..color = const Color(0xFF020208)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Quelques étoiles
    final starPaint = Paint()..color = Colors.white.withOpacity(0.3);
    final rng = math.Random(42);
    for (int i = 0; i < 50; i++) {
      canvas.drawCircle(Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height), 0.8, starPaint);
    }

    // ── Projection 3D simple ─────────────────────
    // Le tuyau est un cylindre horizontal
    final pipeLength = size.width * 0.7;
    final pipeRadius = size.height * 0.12;
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);
    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);

    // Projeter un point 3D → 2D
    Offset project(double x, double y, double z) {
      final rx = x;
      final ry = y * cosX - z * sinX;
      final rz = y * sinX + z * cosX;
      final rx2 = rx * cosY + rz * sinY;
      final rz2 = -rx * sinY + rz * cosY;
      final scale = 600 / (600 + rz2);
      return Offset(cx + rx2 * scale, cy + ry * scale);
    }

    // ── Dessiner le tuyau ────────────────────────
    final nSegments = 32;
    final nSlices   = 20;
    final halfLen   = pipeLength / 2;

    // Faces du cylindre
    for (int s = 0; s < nSlices; s++) {
      for (int r = 0; r < nSegments; r++) {
        final a1 = 2 * math.pi * r / nSegments;
        final a2 = 2 * math.pi * (r + 1) / nSegments;
        final x1 = -halfLen + s * pipeLength / nSlices;
        final x2 = -halfLen + (s + 1) * pipeLength / nSlices;

        final p1 = project(x1, pipeRadius * math.cos(a1), pipeRadius * math.sin(a1));
        final p2 = project(x2, pipeRadius * math.cos(a1), pipeRadius * math.sin(a1));
        final p3 = project(x2, pipeRadius * math.cos(a2), pipeRadius * math.sin(a2));
        final p4 = project(x1, pipeRadius * math.cos(a2), pipeRadius * math.sin(a2));

        final light = (math.cos(a1 + rotY) * 0.5 + 0.5);
        final faceColor = Color.lerp(
          const Color(0xFF0A4060),
          const Color(0xFF22D3EE),
          light * 0.6)!.withOpacity(0.7);

        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..lineTo(p4.dx, p4.dy)
          ..close();

        canvas.drawPath(path, Paint()
          ..color = faceColor
          ..style = PaintingStyle.fill);
        canvas.drawPath(path, Paint()
          ..color = const Color(0xFF22D3EE).withOpacity(0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3);
      }
    }

    // ── Extrémités du tuyau ──────────────────────
    _drawCircleEnd(canvas, project(-halfLen, 0, 0),
      project(-halfLen, pipeRadius, 0), project(-halfLen, 0, pipeRadius));
    _drawCircleEnd(canvas, project(halfLen, 0, 0),
      project(halfLen, pipeRadius, 0), project(halfLen, 0, pipeRadius));

    // ── Caméra (sphère bleue à l'entrée) ─────────
    final camPos = project(-halfLen, 0, 0);
    canvas.drawCircle(camPos, 8, Paint()
      ..color = Colors.blue.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(camPos, 6, Paint()..color = Colors.blue);

    // ── Anomalies (sphères rouges) ────────────────
    for (final a in anomalies) {
      // Position en x selon la distance
      final ratio = longueur > 0 ? (a.dist / longueur).clamp(0.0, 1.0) : 0.5;
      final ax = -halfLen + ratio * pipeLength;
      // Position angulaire pseudo-aléatoire basée sur l'index
      final angle = (a.index * 1.618) % (2 * math.pi);
      final ar = pipeRadius * 0.85;
      final pos = project(ax, ar * math.cos(angle), ar * math.sin(angle));

      final isSelected = selected == a.index;
      final radius     = isSelected ? 10.0 : 7.0;
      final color      = isSelected ? Colors.orange : Colors.red;

      // Halo pulsant
      canvas.drawCircle(pos, radius + 4, Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(pos, radius, Paint()..color = color);

      // Numéro
      final tp = TextPainter(
        text: TextSpan(text: '${a.index + 1}',
          style: TextStyle(color: Colors.white,
            fontSize: isSelected ? 7.0 : 6.0,
            fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas,
        pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawCircleEnd(Canvas canvas, Offset center,
      Offset radiusH, Offset radiusV) {
    // Approximation ellipse pour les extrémités
    final rx = (radiusH - center).distance;
    final ry = (radiusV - center).distance;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      Paint()
        ..color = const Color(0xFF0A2030).withOpacity(0.8)
        ..style = PaintingStyle.fill);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PipePainter old) => true;
}
