// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'pump_debug_screen.dart';

class PumpControlScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final models.Document chantierDoc;
  final double epaisseur;
  final String resinType, userName, piBase;
  final int passNum, passesDone, passes;
  final double longueur, diametre, qteParPasse;

  const PumpControlScreen({
    super.key,
    required this.canalisationDoc,
    required this.chantierDoc,
    required this.epaisseur,
    required this.resinType,
    required this.userName,
    required this.piBase,
    required this.passNum,
    required this.passesDone,
    required this.passes,
    required this.longueur,
    required this.diametre,
    required this.qteParPasse,
  });

  @override
  State<PumpControlScreen> createState() => _PumpControlScreenState();
}

class _PumpControlScreenState extends State<PumpControlScreen> {

  // ── Connexion Pi ──────────────────────────────
  bool _piConnected = false;

  Future<void> _sendCmd(String cmd) async {
    try {
      final resp = await http.post(
        Uri.parse('${widget.piBase}/cmd'),
        headers: {'Content-Type': 'application/json'},
        body: '{"cmd": "$cmd"}',
      ).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) setState(() => _piConnected = true);
    } catch (_) {
      setState(() => _piConnected = false);
    }
  }

  // Convertit le débit commandé (0 – 0.8 L/min) en pourcentage PWM (0 – 100)
  // À ajuster si la correspondance réelle débit/PWM du moteur diffère.
  int _debitToPwmPercent() {
    return ((_debitCommand / 0.8) * 100).round().clamp(0, 100);
  }

  Future<void> _checkPiConnection() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.piBase}/ping'),
      ).timeout(const Duration(seconds: 2));
      setState(() => _piConnected = resp.statusCode == 200);
    } catch (_) {
      setState(() => _piConnected = false);
    }
  }

  // ── Télémétrie réelle (moteur pompe A) ────────────
  bool _arduinoConnected = false;
  int _consecutiveFailures = 0;

  Future<void> _fetchTelemetry() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.piBase}/telemetry'),
      ).timeout(const Duration(seconds: 2));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        setState(() {
          _consecutiveFailures = 0;
          // Le Pi a répondu : il est bien joignable, quel que soit l'état de l'Arduino
          _piConnected = true;
          // État séparé : est-ce que l'Arduino transmet des données fraîches ?
          _arduinoConnected = data['connected'] == true;
          _consoMoteurA = (data['consoMoteurA_percent'] as num?)?.toDouble()
              ?? _consoMoteurA;
        });
      } else {
        _registerFailure();
      }
    } catch (_) {
      // Erreur réseau/timeout : peut être une micro-coupure ponctuelle,
      // on ne bascule "hors ligne" qu'après plusieurs échecs d'affilée.
      if (!mounted) return;
      _registerFailure();
    }
  }

  void _registerFailure() {
    if (!mounted) return;
    setState(() {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 2) {
        _piConnected = false;
        _arduinoConnected = false;
      }
    });
  }

  // ── Commandes opérateur ───────────────────────
  bool   _isPumpOn       = false;
  double _debitCommand   = 0.0;   // 0.0 – 0.8 L/min
  double _vitesseCommand = 0.0;   // 0.0 – 1.2 m/min

  // ── Métriques avancement ──────────────────────
  double _metersDone  = 0;
  double _metersLeft  = 0;
  double _timeElapsed = 0;
  double _resinConso  = 0;

  // ── Télémétrie simulée ────────────────────────
  double _consoMoteurA            = 0.0;
  double _consoMoteurB            = 0.0;
  bool   _niveauResineOk          = true;
  bool   _niveauDurcisseurOk      = true;
  double _tempNourriceResine      = 20.0;
  double _tempNourriceDurcisseur  = 20.0;
  double _tempCouverture1         = 25.0;
  double _tempCouverture2         = 25.0;
  double _debitReel               = 0.0;

  final _random = math.Random();
  Timer? _timer;
  Timer? _telemetryTimer;

  final TextEditingController _debitFieldCtrl = TextEditingController();
  final TextEditingController _vitesseFieldCtrl = TextEditingController();
  final FocusNode _debitFocus = FocusNode();
  final FocusNode _vitesseFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _metersLeft = widget.longueur;
    _resinConso = widget.passesDone * widget.qteParPasse;
    _debitFieldCtrl.text = _debitCommand.toStringAsFixed(2);
    _vitesseFieldCtrl.text = _vitesseCommand.toStringAsFixed(2);
    _debitFocus.addListener(() {
      if (!_debitFocus.hasFocus) _applyDebitInput(_debitFieldCtrl.text);
    });
    _vitesseFocus.addListener(() {
      if (!_vitesseFocus.hasFocus) _applyVitesseInput(_vitesseFieldCtrl.text);
    });
    _checkPiConnection();
    _startTimer();
    _fetchTelemetry();
    _telemetryTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _fetchTelemetry());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _telemetryTimer?.cancel();
    _debitFieldCtrl.dispose();
    _vitesseFieldCtrl.dispose();
    _debitFocus.dispose();
    _vitesseFocus.dispose();
    super.dispose();
  }

  // Applique une valeur de débit saisie manuellement (clavier)
  void _applyDebitInput(String text) {
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) {
      _debitFieldCtrl.text = _debitCommand.toStringAsFixed(2);
      return;
    }
    final clamped = parsed.clamp(0.0, 0.8);
    setState(() => _debitCommand = clamped);
    _debitFieldCtrl.text = clamped.toStringAsFixed(2);
    if (_isPumpOn) _sendCmd('SPEED=${_debitToPwmPercent()}');
  }

  // Applique une valeur de vitesse saisie manuellement (clavier)
  void _applyVitesseInput(String text) {
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) {
      _vitesseFieldCtrl.text = _vitesseCommand.toStringAsFixed(2);
      return;
    }
    final clamped = parsed.clamp(0.0, 1.2);
    setState(() => _vitesseCommand = clamped);
    _vitesseFieldCtrl.text = clamped.toStringAsFixed(2);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        // ── Télémétrie simulée (pompe B, débit, températures) ──
        // Note : _consoMoteurA n'est plus simulé ici, il vient du
        // capteur réel via _fetchTelemetry() / _telemetryTimer.
        if (_isPumpOn) {
          _consoMoteurB = 42.0 + (_debitCommand * 50) + _random.nextDouble() * 5;
          _debitReel    = _debitCommand > 0
              ? (_debitCommand - 0.02 + _random.nextDouble() * 0.04).clamp(0, double.infinity)
              : 0.0;
          if (_tempNourriceResine < 35.0)     _tempNourriceResine     += 0.05;
          if (_tempNourriceDurcisseur < 35.0) _tempNourriceDurcisseur += 0.05;
        } else {
          _consoMoteurB = 0.0;
          _debitReel    = 0.0;
        }

        // ── Avancement tracteur ────────────────
        if (_isPumpOn && _vitesseCommand > 0) {
          final delta = _vitesseCommand / 60; // 1 seconde → m
          _metersDone += delta;
          _metersLeft  = (widget.longueur - _metersDone).clamp(0, widget.longueur);
          _timeElapsed += 1 / 60;
          _resinConso  = (widget.passesDone * widget.qteParPasse)
              + _metersDone * (math.pi * widget.diametre * widget.epaisseur / 1000);

          // Passe terminée automatiquement
          if (_metersLeft <= 0.001) {
            _isPumpOn = false;
            _sendCmd('SPEED=0');
            _timer?.cancel();
            _showPasseTermineeDialog();
          }
        }
      });
    });
  }

  void _togglePump() {
    setState(() => _isPumpOn = !_isPumpOn);
    _sendCmd(_isPumpOn ? 'SPEED=${_debitToPwmPercent()}' : 'SPEED=0');
  }

  String _fmt(double mins) {
    final m = mins.floor();
    final s = ((mins - m) * 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Dialog fin de passe ───────────────────────
  Future<void> _showPasseTermineeDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.green.withOpacity(0.5), width: 1)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 22),
          SizedBox(width: 8),
          Text('PASSE TERMINÉE',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ]),
        content: Text(
          'La passe N°${widget.passNum} est complète.\n'
          '${_metersDone.toStringAsFixed(2)} m résinés en ${_fmt(_timeElapsed)}.',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // fermer dialog
              Navigator.pop(context, true); // retour à pump_operation avec succès
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('RETOUR AUX PASSES',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ── Quitter manuellement ──────────────────────
  Future<void> _confirmExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.orange.withOpacity(0.5))),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('QUITTER LA PASSE ?',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13)),
        ]),
        content: Text(
          'La pompe sera arrêtée et la passe N°${widget.passNum} sera interrompue.',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continuer',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('QUITTER',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      _sendCmd('SPEED=0');
      Navigator.pop(context, false); // retour sans valider la passe
    }
  }

  @override
  Widget build(BuildContext context) {
    final resinName = widget.resinType == 'spraycoat_plus'
        ? 'Spraycoat+'
        : 'Spraycoat Flex';

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: _confirmExit),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('PASSE ',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
            Text('N°${widget.passNum}',
                style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
            Text(' / ${widget.passes}',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ]),
          Row(children: [
            _headerBadge('DN${widget.diametre.toInt()}',
                const Color(0xFF22D3EE)),
            const SizedBox(width: 6),
            _headerBadge(resinName, Colors.white),
            const SizedBox(width: 6),
            _headerBadge('#${widget.canalisationDoc.data['label'] ?? '—'}',
                Colors.purple),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.white70, size: 20),
            tooltip: 'Debug Arduino/Pi',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PumpDebugScreen(piBase: widget.piBase),
              ),
            ),
          ),
          Container(
              margin: const EdgeInsets.only(right: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                Text(_piConnected ? 'PI CONNECTÉ' : 'PI HORS LIGNE',
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
          // ── Avancement passe ────────────────────
          _buildProgressBar(),
          const SizedBox(height: 14),

          // ── Contrôles (bouton marche/arrêt) ─────
          _buildOperatorCommands(),
          const SizedBox(height: 14),

          // ── Commandes de vitesse (pleine largeur) ──
          _buildSpeedControls(),
          const SizedBox(height: 14),

          // ── Métriques (débit mesuré + réservoirs) ──
          _buildMetrics(),
          const SizedBox(height: 14),

          // ── Supervision hardware ────────────────
          _buildHardwareSupervision(),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ── Barre de progression passe ─────────────────
  Widget _buildProgressBar() {
    final progress = widget.longueur > 0
        ? (_metersDone / widget.longueur).clamp(0.0, 1.0)
        : 0.0;
    final remainingMins =
        _vitesseCommand > 0 ? _metersLeft / _vitesseCommand : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _isPumpOn
                  ? const Color(0xFF22D3EE).withOpacity(0.3)
                  : Colors.white.withOpacity(0.06))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('PASSE N°${widget.passNum} — AVANCEMENT',
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
          Text('${(progress * 100).toStringAsFixed(1)} %',
              style: const TextStyle(
                  color: Color(0xFF22D3EE),
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.05),
            color: _isPumpOn
                ? const Color(0xFF22D3EE)
                : const Color(0xFF22D3EE).withOpacity(0.4),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _miniStat('Résinés',
              '${_metersDone.toStringAsFixed(2)} m', const Color(0xFF22D3EE)),
          _miniStat('Restants',
              '${_metersLeft.toStringAsFixed(2)} m', Colors.white),
          _miniStat('Écoulé', _fmt(_timeElapsed), Colors.white),
          _miniStat('Restant', _fmt(remainingMins), Colors.white),
          _miniStat('Résine',
              '${_resinConso.toStringAsFixed(2)} L', Colors.purpleAccent),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
        child: Column(children: [
      Text(label,
          style: TextStyle(
              color: Colors.grey[600],
              fontSize: 7,
              fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center),
      ),
    ]));
  }

  // ── Contrôles opérateur ────────────────────────
  Widget _buildOperatorCommands() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.tune, color: Color(0xFF22D3EE), size: 13),
          const SizedBox(width: 6),
          Text('CONTRÔLES',
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 14),

        // ── Bouton On/Off moteur ────────────────
        GestureDetector(
          onTap: _togglePump,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              color: _isPumpOn
                  ? Colors.red.withOpacity(0.15)
                  : Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _isPumpOn
                      ? Colors.red.withOpacity(0.6)
                      : Colors.green.withOpacity(0.5),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: (_isPumpOn ? Colors.red : Colors.green)
                        .withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 0),
              ],
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
              Icon(
                _isPumpOn ? Icons.stop_circle : Icons.play_circle,
                color: _isPumpOn ? Colors.redAccent : Colors.greenAccent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isPumpOn ? 'ARRÊTER MOTEUR' : 'DÉMARRER MOTEUR',
                  style: TextStyle(
                      color: _isPumpOn ? Colors.redAccent : Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Commandes de vitesse (pleine largeur, sous les cuves) ──
  Widget _buildSpeedControls() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.speed, color: Color(0xFF22D3EE), size: 13),
          const SizedBox(width: 6),
          Text('COMMANDES DE VITESSE',
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Débit
          Expanded(child: Column(children: [
            SpeedometerGauge(
              currentSpeed: _debitCommand,
              maxSpeed: 0.8,
              unit: 'L/min',
              color: const Color(0xFF22D3EE),
              size: 170,
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.water_drop, color: Color(0xFF22D3EE), size: 13),
              const SizedBox(width: 4),
              Text('Débit',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ]),
            const SizedBox(height: 3),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _debitFieldCtrl,
                focusNode: _debitFocus,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontWeight: FontWeight.w900,
                    fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 8),
                  suffixText: 'L/min',
                  suffixStyle:
                      TextStyle(color: Colors.grey[500], fontSize: 9),
                  filled: true,
                  fillColor: Colors.black45,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: const Color(0xFF22D3EE).withOpacity(0.3))),
                ),
                onSubmitted: _applyDebitInput,
              ),
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
              ),
              child: Slider(
                value: _debitCommand,
                min: 0.0,
                max: 0.8,
                divisions: 80,
                activeColor: const Color(0xFF22D3EE),
                inactiveColor: Colors.grey[800],
                onChanged: (val) => setState(() {
                  _debitCommand = val;
                  if (!_debitFocus.hasFocus) {
                    _debitFieldCtrl.text = val.toStringAsFixed(2);
                  }
                }),
                onChangeEnd: (val) {
                  if (_isPumpOn) _sendCmd('SPEED=${_debitToPwmPercent()}');
                },
              ),
            ),
          ])),

          const SizedBox(width: 16),

          // Vitesse
          Expanded(child: Column(children: [
            SpeedometerGauge(currentSpeed: _vitesseCommand, size: 170),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.speed, color: Color(0xFFEAB308), size: 13),
              const SizedBox(width: 4),
              Text('Vitesse',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ]),
            const SizedBox(height: 3),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _vitesseFieldCtrl,
                focusNode: _vitesseFocus,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: Color(0xFFEAB308),
                    fontWeight: FontWeight.w900,
                    fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 8),
                  suffixText: 'm/min',
                  suffixStyle:
                      TextStyle(color: Colors.grey[500], fontSize: 9),
                  filled: true,
                  fillColor: Colors.black45,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: const Color(0xFFEAB308).withOpacity(0.3))),
                ),
                onSubmitted: _applyVitesseInput,
              ),
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
              ),
              child: Slider(
                value: _vitesseCommand,
                min: 0.0,
                max: 1.2,
                divisions: 120,
                activeColor: const Color(0xFFEAB308),
                inactiveColor: Colors.grey[800],
                onChanged: (val) => setState(() {
                  _vitesseCommand = val;
                  if (!_vitesseFocus.hasFocus) {
                    _vitesseFieldCtrl.text = val.toStringAsFixed(2);
                  }
                }),
              ),
            ),
          ])),
        ]),
      ]),
    );
  }

  // ── Métriques résine ───────────────────────────
  Widget _buildMetrics() {
    final totalResin = widget.qteParPasse * widget.passes;
    final resinLeft  = (totalResin - _resinConso).clamp(0.0, totalResin);
    final fillRatio  = totalResin > 0 ? resinLeft / totalResin : 0.0;

    return Column(children: [
      // Débit réel en évidence
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFFEAB308).withOpacity(0.25))),
        child: Column(children: [
          Text('DÉBIT MESURÉ',
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_debitReel.toStringAsFixed(3),
                style: const TextStyle(
                    color: Color(0xFFEAB308),
                    fontSize: 30,
                    fontWeight: FontWeight.w900)),
            const Padding(
              padding: EdgeInsets.only(top: 10, left: 4),
              child: Text('L/min',
                  style: TextStyle(
                      color: Color(0xFFEAB308), fontSize: 11)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 10),

      // Cuves résine / durcisseur
      Row(children: [
        Expanded(
            child: TankLevelGauge(
                label: 'RÉSINE',
                fillRatio: fillRatio,
                color: Colors.purpleAccent,
                isSensorOk: _niveauResineOk,
                capacityLiters: 6.5)),
        const SizedBox(width: 10),
        Expanded(
            child: TankLevelGauge(
                label: 'DURCIS.',
                fillRatio: fillRatio,
                color: const Color(0xFF22D3EE),
                isSensorOk: _niveauDurcisseurOk,
                capacityLiters: 3.25)),
      ]),
    ]);
  }

  // ── Supervision hardware ───────────────────────
  Widget _buildHardwareSupervision() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF101015),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.memory, color: Color(0xFF22D3EE), size: 13),
          const SizedBox(width: 6),
          Text('SUPERVISION HARDWARE',
              style: TextStyle(
                  color: Colors.cyan[100],
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 8),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 8),

        // Jauges moteurs
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildMotorGauge('POMPE A', _consoMoteurA)),
          const SizedBox(width: 14),
          Expanded(child: _buildMotorGauge('POMPE B', _consoMoteurB)),
        ]),

        const SizedBox(height: 8),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 8),

        // Températures — 2 colonnes x 2 lignes
        Row(children: [
          Expanded(child: _buildTempBadge('Nourrice Résine',  _tempNourriceResine,     iconColor: const Color(0xFFA855F7))),
          const SizedBox(width: 6),
          Expanded(child: _buildTempBadge('Nourrice Durcis.', _tempNourriceDurcisseur, iconColor: const Color(0xFF22D3EE))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _buildTempBadge('Couverture 1', _tempCouverture1, iconColor: const Color(0xFFA855F7))),
          const SizedBox(width: 6),
          Expanded(child: _buildTempBadge('Couverture 2', _tempCouverture2, iconColor: const Color(0xFF22D3EE))),
        ]),
      ]),
    );
  }

  // ── Widgets utilitaires ────────────────────────
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

  Widget _buildMotorGauge(String label, double percent) {
    final Color barColor = percent > 80.0
        ? Colors.redAccent
        : percent > 60.0
            ? Colors.orangeAccent
            : Colors.greenAccent;
    return Row(children: [
      Expanded(
        flex: 5,
        child: Text(label,
            style: TextStyle(
                color: Colors.grey[500],
                fontSize: 8,
                fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: Colors.white.withOpacity(0.05),
            color: barColor,
            minHeight: 5,
          ),
        ),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 30,
        child: Text('${percent.toInt()}%',
            style: TextStyle(
                color: barColor,
                fontSize: 9,
                fontWeight: FontWeight.w900),
            textAlign: TextAlign.right),
      ),
    ]);
  }

  Widget _buildTempBadge(String label, double temp, {Color iconColor = const Color(0xFFA855F7)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: iconColor.withOpacity(0.25))),
      child: Row(children: [
        Icon(Icons.thermostat, color: iconColor, size: 13),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 7,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            Text('${temp.toStringAsFixed(1)}°C',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }
}

// =========================================================
// WIDGETS EXTERNES (réutilisés depuis pump_operation_screen)
// =========================================================

class SpeedometerGauge extends StatelessWidget {
  final double currentSpeed;
  final double maxSpeed;
  final String unit;
  final Color color;
  final double size;

  const SpeedometerGauge({
    super.key,
    required this.currentSpeed,
    this.maxSpeed = 1.2,
    this.unit = 'm/min',
    this.color = const Color(0xFFEAB308),
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final scale = size / 120;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _SpeedometerPainter(currentSpeed, maxSpeed, color),
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          currentSpeed.toStringAsFixed(2),
          style: TextStyle(
              color: color,
              fontSize: 16 * scale,
              fontWeight: FontWeight.w900),
        ),
        Text(unit,
            style: TextStyle(
                color: Colors.grey[500],
                fontSize: 9 * scale,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final Color color;
  _SpeedometerPainter(this.speed, this.maxSpeed, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center     = Offset(size.width / 2, size.height / 2);
    final radius     = size.width / 2;
    final startAngle = math.pi * 0.75;
    final sweepAngle = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle, sweepAngle, false,
      Paint()
        ..color = Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    final ratio    = (speed / maxSpeed).clamp(0.0, 1.0);
    final progress = ratio * sweepAngle;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle, progress, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    final angle      = startAngle + progress;
    final needleEnd  = Offset(
      center.dx + (radius - 18) * math.cos(angle),
      center.dy + (radius - 18) * math.sin(angle),
    );
    canvas.drawLine(center, needleEnd,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);

    canvas.drawCircle(center, 4, Paint()..color = color);
    canvas.drawCircle(center, 2, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter old) =>
      old.speed != speed || old.color != color;
}

class TankLevelGauge extends StatelessWidget {
  final String label;
  final double fillRatio;
  final Color color;
  final bool isSensorOk;
  final double capacityLiters;

  const TankLevelGauge({
    super.key,
    required this.label,
    required this.fillRatio,
    required this.color,
    required this.isSensorOk,
    required this.capacityLiters,
  });

  @override
  Widget build(BuildContext context) {
    final displayRatio = isSensorOk ? fillRatio.clamp(0.0, 1.0) : 0.0;
    final themeColor   = isSensorOk ? color : Colors.redAccent;

    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final w = (constraints.maxWidth * 0.7).clamp(40.0, 70.0);
        return Container(
          height: 120,
          width: w,
          decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: [
                BoxShadow(
                    color: themeColor.withOpacity(0.15),
                    blurRadius: 10,
                    spreadRadius: 1)
              ]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(alignment: Alignment.bottomCenter, children: [
              FractionallySizedBox(
                heightFactor: displayRatio,
                widthFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                        themeColor.withOpacity(0.6),
                        themeColor
                      ])),
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(height: 2, color: Colors.white54)),
                ),
              ),
              Positioned(
                left: 4, top: 4, bottom: 4,
                width: 12,
                child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10))),
              ),
              Center(
                child: isSensorOk
                    ? Text('${(displayRatio * capacityLiters).toStringAsFixed(2)} L',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4)
                            ]))
                    : const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 28),
              ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: isSensorOk
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4)),
        child: Text(
          isSensorOk ? 'OK' : 'VIDE',
          style: TextStyle(
              color: isSensorOk ? Colors.greenAccent : Colors.redAccent,
              fontSize: 9,
              fontWeight: FontWeight.w900),
        ),
      ),
    ]);
  }
}
