// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lang_service.dart';

class TutorialStep {
  final String title;
  final String description;
  final Offset targetOffset;
  final double targetSize;
  final VoidCallback? onBefore;

  const TutorialStep({
    required this.title,
    required this.description,
    this.targetOffset = const Offset(0.5, 0.5),
    this.targetSize   = 50,
    this.onBefore,
  });
}

class BzTutorial extends StatefulWidget {
  final String tutorialKey;
  final List<TutorialStep> steps;
  final Widget child;

  const BzTutorial({
    super.key,
    required this.tutorialKey,
    required this.steps,
    required this.child,
  });

  static Future<bool> shouldShow(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('tutorial_done_$key') ?? false);
  }

  static Future<void> markDone(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_done_$key', true);
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('tutorial_done_'));
    for (final k in keys) await prefs.remove(k);
  }

  @override
  State<BzTutorial> createState() => BzTutorialState();
}

class BzTutorialState extends State<BzTutorial>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  int  _step = 0;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _arrowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _arrowAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoShow());
  }

  @override
  void dispose() {
    _removeOverlay();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkAutoShow() async {
    final should = await BzTutorial.shouldShow(widget.tutorialKey);
    if (should && mounted) show();
  }

  void show() {
    _step = 0;
    _removeOverlay();
    widget.steps[0].onBefore?.call();
    _insertOverlay();
    _ctrl.forward(from: 0);
  }

  void _insertOverlay() {
    final lang = LangService();
    _entry = OverlayEntry(builder: (_) => _TutorialOverlay(
      steps:       widget.steps,
      stepIndex:   _step,
      fadeAnim:    _fadeAnim,
      arrowAnim:   _arrowAnim,
      onNext:      _next,
      onDismiss:   _dismiss,
      skipLabel:   lang.t('tutorialSkip'),
      nextLabel:   lang.t('tutorialNext'),
      finishLabel: lang.t('tutorialFinish'),
    ));
    Overlay.of(context).insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _next() {
    if (_step < widget.steps.length - 1) {
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        _step++;
        widget.steps[_step].onBefore?.call();
        _removeOverlay();
        _insertOverlay();
        _ctrl.forward(from: 0);
      });
    } else {
      _dismiss();
    }
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    _removeOverlay();
    await BzTutorial.markDone(widget.tutorialKey);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Overlay affiché par-dessus tout ───────────────
class _TutorialOverlay extends StatelessWidget {
  final List<TutorialStep> steps;
  final int stepIndex;
  final Animation<double> fadeAnim;
  final Animation<double> arrowAnim;
  final VoidCallback onNext;
  final VoidCallback onDismiss;
  final String skipLabel;
  final String nextLabel;
  final String finishLabel;

  const _TutorialOverlay({
    required this.steps,
    required this.stepIndex,
    required this.fadeAnim,
    required this.arrowAnim,
    required this.onNext,
    required this.onDismiss,
    required this.skipLabel,
    required this.nextLabel,
    required this.finishLabel,
  });

  @override
  Widget build(BuildContext context) {
    final step = steps[stepIndex];
    final size = MediaQuery.of(context).size;
    final targetCenter = Offset(
      size.width  * step.targetOffset.dx,
      size.height * step.targetOffset.dy);

    final bubbleIsBelow = step.targetOffset.dy < 0.5;
    final bubbleTop = bubbleIsBelow
      ? targetCenter.dy + step.targetSize + 24
      : targetCenter.dy - step.targetSize - 190;
    final bubbleTop2 = bubbleTop.clamp(80.0, size.height - 230);

    final arrowFromY = bubbleIsBelow ? bubbleTop2 : bubbleTop2 + 175;
    final arrowFrom  = Offset(size.width / 2, arrowFromY);

    return Material(
      color: Colors.transparent,
      child: Stack(children: [

        // Fond sombre semi-transparent (bloque le blanc du fond)
        FadeTransition(
          opacity: fadeAnim,
          child: Container(
            width: size.width,
            height: size.height,
            color: Colors.black.withOpacity(0.72),
          ),
        ),

        // Flèche animée + cercle cible
        AnimatedBuilder(
          animation: arrowAnim,
          builder: (_, __) => CustomPaint(
            size: size,
            painter: _ArrowPainter(
              from:     arrowFrom,
              to:       targetCenter,
              radius:   step.targetSize,
              progress: arrowAnim.value,
            ),
          ),
        ),

        // Bulle (Positioned doit être enfant direct du Stack)
        Positioned(
          top:   bubbleTop2,
          left:  24,
          right: 24,
          child: FadeTransition(
            opacity: fadeAnim,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.7)),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFEAB308).withOpacity(0.25),
                  blurRadius: 20)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAB308),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('${stepIndex + 1} / ${steps.length}',
                      style: const TextStyle(color: Colors.black,
                        fontSize: 10, fontWeight: FontWeight.w900))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step.title,
                    style: const TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w900))),
                  GestureDetector(
                    onTap: onDismiss,
                    child: Icon(Icons.close, color: Colors.grey[600], size: 18)),
                ]),
                const SizedBox(height: 10),
                Text(step.description,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5)),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton(
                    onPressed: onDismiss,
                    child: Text(skipLabel,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12))),
                  GestureDetector(
                    onTap: onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAB308),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        stepIndex < steps.length - 1 ? nextLabel : finishLabel,
                        style: const TextStyle(color: Colors.black,
                          fontWeight: FontWeight.w900, fontSize: 12)))),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Painter flèche courbée + cercle cible ─────────
class _ArrowPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double radius;
  final double progress;

  const _ArrowPainter({
    required this.from,
    required this.to,
    required this.radius,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    // Cercle autour de la cible
    canvas.drawCircle(to, radius * progress,
      Paint()
        ..color = const Color(0xFFEAB308).withOpacity(0.2 * progress)
        ..style = PaintingStyle.fill);
    canvas.drawCircle(to, radius * progress,
      Paint()
        ..color = const Color(0xFFEAB308).withOpacity(0.9 * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);

    // Direction
    final dx   = to.dx - from.dx;
    final dy   = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 10) return;

    // Point d'arrivée à la bordure du cercle
    final end = Offset(
      to.dx - (dx / dist) * radius,
      to.dy - (dy / dist) * radius);

    // Courbe de Bézier
    final ctrl = Offset(
      (from.dx + end.dx) / 2 + (dy / dist) * 50,
      (from.dy + end.dy) / 2 - (dx / dist) * 50);

    final path = Path()..moveTo(from.dx, from.dy);
    path.quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);

    final metrics = path.computeMetrics().first;
    final partial = metrics.extractPath(0, metrics.length * progress.clamp(0.0, 1.0));
    canvas.drawPath(partial,
      Paint()
        ..color = const Color(0xFFEAB308).withOpacity(0.9)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);

    // Pointe de flèche
    if (progress > 0.75) {
      final op    = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
      final angle = math.atan2(end.dy - ctrl.dy, end.dx - ctrl.dx);
      const sz    = 10.0;
      final head  = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - sz * math.cos(angle - 0.4),
                 end.dy - sz * math.sin(angle - 0.4))
        ..lineTo(end.dx - sz * math.cos(angle + 0.4),
                 end.dy - sz * math.sin(angle + 0.4))
        ..close();
      canvas.drawPath(head,
        Paint()
          ..color = const Color(0xFFEAB308).withOpacity(op)
          ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter o) =>
    o.progress != progress || o.from != from || o.to != to;
}
