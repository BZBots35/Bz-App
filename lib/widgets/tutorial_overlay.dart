// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final TutorialBubblePosition bubblePosition;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.bubblePosition = TutorialBubblePosition.bottom,
  });
}

enum TutorialBubblePosition { top, bottom, left, right }

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final String tutorialKey;
  final VoidCallback? onComplete;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.tutorialKey,
    this.onComplete,
  });

  static Future<bool> shouldShow(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('tutorial_done_$key') ?? false);
  }

  static Future<void> markDone(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_done_$key', true);
  }

  static Future<void> reset(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tutorial_done_$key');
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  Rect? _targetRect;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetRect();
      _animCtrl.forward();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _updateTargetRect() {
    final step = widget.steps[_currentStep];
    final ctx  = step.targetKey.currentContext;
    if (ctx == null) {
      setState(() => _targetRect = null);
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    setState(() {
      _targetRect = Rect.fromLTWH(
        offset.dx, offset.dy,
        box.size.width, box.size.height);
    });
  }

  Future<void> _next() async {
    await _animCtrl.reverse();
    if (_currentStep < widget.steps.length - 1) {
      setState(() => _currentStep++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateTargetRect();
        _animCtrl.forward();
      });
    } else {
      await _complete();
    }
  }

  Future<void> _complete() async {
    await TutorialOverlay.markDone(widget.tutorialKey);
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final step   = widget.steps[_currentStep];
    final size   = MediaQuery.of(context).size;
    final isLast = _currentStep == widget.steps.length - 1;

    // Si l'élément cible n'est pas trouvé, affiche quand même la bulle au centre
    final effectiveRect = _targetRect ??
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 60, height: 60);

    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(children: [
        // Overlay sombre avec spotlight
        CustomPaint(
          size: size,
          painter: _SpotlightPainter(targetRect: effectiveRect)),

        // Zone cliquable sur spotlight
        Positioned(
          left:  effectiveRect.left  - 8,
          top:   effectiveRect.top   - 8,
          width: effectiveRect.width  + 16,
          height: effectiveRect.height + 16,
          child: GestureDetector(
            onTap: _next,
            child: Container(color: Colors.transparent))),

        // Bulle
        _buildBubble(step, size, isLast, effectiveRect),

        // Bouton passer
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: GestureDetector(
            onTap: _complete,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4))),
              child: const Text('Passer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  fontFamily: 'Roboto'))))),
      ]),
    );
  }

  Widget _buildBubble(TutorialStep step, Size size, bool isLast, Rect target) {
    const bubbleW = 270.0;
    const arrowH  = 10.0;
    const padding = 16.0;

    // Calcul position bulle
    double left, top;
    bool showArrowAbove = false; // flèche au-dessus de la bulle (pointe vers le haut)
    bool showArrowBelow = false; // flèche en-dessous de la bulle (pointe vers le bas)

    final centerX = target.left + target.width / 2;
    final spaceBelow = size.height - target.bottom;
    final spaceAbove = target.top;

    if (step.bubblePosition == TutorialBubblePosition.bottom ||
        (step.bubblePosition != TutorialBubblePosition.top && spaceBelow > 200)) {
      // Bulle en dessous
      showArrowAbove = true;
      top  = target.bottom + arrowH + 8;
      left = (centerX - bubbleW / 2).clamp(padding, size.width - bubbleW - padding);
    } else {
      // Bulle au-dessus
      showArrowBelow = true;
      top  = target.top - 180 - arrowH - 8;
      left = (centerX - bubbleW / 2).clamp(padding, size.width - bubbleW - padding);
    }

    // Sécurité verticale
    top = top.clamp(
      MediaQuery.of(context).padding.top + 50,
      size.height - 200);

    // Point de la flèche
    final arrowX = (centerX - left).clamp(20.0, bubbleW - 20);

    return Positioned(
      left: left,
      top:  top,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Flèche vers le haut (bulle en dessous de l'élément)
            if (showArrowAbove)
              Padding(
                padding: EdgeInsets.only(left: arrowX - 8),
                child: CustomPaint(
                  size: const Size(16, arrowH),
                  painter: _ArrowPainter(pointUp: true))),

            // Corps bulle
            Container(
              width: bubbleW,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8))]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Indicateur étapes
                Row(children: [
                  ...List.generate(widget.steps.length, (i) =>
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 4),
                      width:  i == _currentStep ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _currentStep
                          ? const Color(0xFF22D3EE)
                          : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(3)))),
                  const Spacer(),
                  Text('${_currentStep + 1}/${widget.steps.length}',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10,
                      decoration: TextDecoration.none,
                      fontFamily: 'Roboto')),
                ]),
                const SizedBox(height: 10),

                // Titre
                Text(step.title,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                    fontFamily: 'Roboto')),
                const SizedBox(height: 6),

                // Description
                Text(step.description,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.5,
                    decoration: TextDecoration.none,
                    fontFamily: 'Roboto')),
                const SizedBox(height: 14),

                // Bouton
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22D3EE),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    child: Text(
                      isLast ? 'Terminer ✓' : 'Suivant →',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        decoration: TextDecoration.none,
                        fontFamily: 'Roboto')))),
              ])),

            // Flèche vers le bas (bulle au-dessus de l'élément)
            if (showArrowBelow)
              Padding(
                padding: EdgeInsets.only(left: arrowX - 8),
                child: CustomPaint(
                  size: const Size(16, arrowH),
                  painter: _ArrowPainter(pointUp: false))),
          ]))));
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  const _SpotlightPainter({required this.targetRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Overlay sombre
    final paint = Paint()..color = Colors.black.withOpacity(0.78);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Découpe spotlight
    final spotPaint = Paint()..blendMode = BlendMode.clear;
    final spotRect  = targetRect.inflate(10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(spotRect, const Radius.circular(14)),
      spotPaint);

    // Bordure cyan
    final borderPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(spotRect, const Radius.circular(14)),
      borderPaint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
    old.targetRect != targetRect;
}

class _ArrowPainter extends CustomPainter {
  final bool pointUp;
  const _ArrowPainter({required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path();
    if (pointUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pointUp != pointUp;
}
