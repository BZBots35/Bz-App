// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';

class PumpOperationScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final models.Document chantierDoc;
  final double epaisseur;
  final String resinType, userName;
  const PumpOperationScreen({super.key,
    required this.canalisationDoc, required this.chantierDoc,
    required this.epaisseur, required this.resinType,
    required this.userName});
  @override
  State<PumpOperationScreen> createState() => _PumpOperationScreenState();
}

class _PumpOperationScreenState extends State<PumpOperationScreen> {
  final _service = PumpService();

  // ── Connexion Pi ──────────────────────────────
  static const String _piBase = 'http://192.168.5.37:5000';
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

  // Paramètres de la canalisation
  late double _longueur;
  late double _diametre;
  late int    _passes;
  late String _label;

  // État simulation
  int    _pumpPower     = 100;
  int    _currentPass   = 0;   // 0 = aucune passe active
  int    _passesDone    = 0;
  bool   _isRunning     = false;
  bool   _isPaused      = false;
  Timer? _timer;

  // Compteurs live
  double _metersDone    = 0;
  double _metersLeft    = 0;
  double _timeElapsed   = 0; // en minutes
  double _resinConso    = 0;

  // Débit pompe (L/min)
  static const double _maxFlowRate = 0.5;

  @override
  void initState() {
    super.initState();
    _checkPiConnection();
    final d   = widget.canalisationDoc.data;
    _label    = d['label']    as String? ?? '';
    _longueur = double.tryParse(d['longueur'] as String? ?? '10') ?? 10;
    _diametre = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
    _passes   = d['passes']   as int?    ?? 4;
    _metersLeft = _longueur;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _Q => _maxFlowRate * (_pumpPower / 100);
  double get _vitesse {
    if (_diametre <= 0 || widget.epaisseur <= 0) return 0;
    return (1000 * _Q) / (math.pi * _diametre * widget.epaisseur);
  }
  double get _qteParPasse =>
    _longueur * (math.pi * _diametre * widget.epaisseur / 1000);

  String _fmt(double mins) {
    final m = mins.floor();
    final s = ((mins - m) * 60).round();
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  // ── Démarrer une passe ─────────────────────────
  void _startPass(int passNum) {
    if (_isRunning) return;
    setState(() {
      _currentPass = passNum;
      _isRunning   = true;
      _isPaused    = false;
      _metersDone  = 0;
      _metersLeft  = _longueur;
      _timeElapsed = 0;
      _resinConso  = (_passesDone) * _qteParPasse;
    });
    // Envoyer commande démarrage à l'Arduino via Pi
    _sendCmd('1');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isRunning || _isPaused) return;
      final v = _vitesse;
      if (v <= 0) return;
      setState(() {
        final delta = v * (0.05 / 60); // 50ms en minutes
        _metersDone  += delta;
        _metersLeft   = (_longueur - _metersDone).clamp(0, _longueur);
        _timeElapsed += 0.05 / 60;
        _resinConso   = (_passesDone * _qteParPasse)
          + _metersDone * (math.pi * _diametre * widget.epaisseur / 1000);

        if (_metersLeft <= 0.001) {
          _timer?.cancel();
          _isRunning  = false;
          _passesDone++;
          _sendCmd('6'); // ← ajoute cette ligne
         if (_passesDone >= _passes) {
         _markTermine();
  }
}
      });
    });
  }

  void _stopPass() {
    _timer?.cancel();
    setState(() { _isRunning = false; });
    // Arrêter la pompe Arduino
    _sendCmd('6');
    _service.updateCanalisation(widget.canalisationDoc.$id,
      statut: 'en_cours');
  }

  void _resetPass() {
    setState(() {
      _metersDone = 0;
      _metersLeft = _longueur;
      _timeElapsed = 0;
    });
  }

  Future<void> _markTermine() async {
    await _service.updateCanalisation(widget.canalisationDoc.$id,
      statut: 'termine');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Canalisation terminée !'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating));
      Navigator.pop(context);
    }
  }

  void _setPumpPower(int power) {
    setState(() => _pumpPower = power);
    // Informer le Pi du changement de puissance (futur usage)
    if (_isRunning) _sendCmd('1');
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
            Text('PASSE $passNum — VÉRIFICATION',
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 13,
                letterSpacing: 1)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Avant de démarrer la passe $passNum, '
              'vérifiez que la résine est correctement préparée '
              'et que la pompe est prête.',
              style: TextStyle(color: Colors.grey[400], fontSize: 12,
                height: 1.5)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setModal(() => checked = !checked),
              child: Row(children: [
                Container(
                  width: 20, height: 20,
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
                const Expanded(child: Text('Résine prête et vérifiée',
                  style: TextStyle(color: Colors.white, fontSize: 12))),
              ]),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: checked
                ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.grey.withOpacity(0.2)),
              child: const Text('DÉMARRER', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 11,
                letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) _startPass(passNum);
  }

  @override
  Widget build(BuildContext context) {
    final resinName = widget.resinType == 'spraycoat_plus'
      ? 'Spraycoat+' : 'Spraycoat Flex';
    final totalEp = (widget.epaisseur * _passes).toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          }),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('COATING ', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 14)),
            Text('#${widget.canalisationDoc.data['label'] ?? '—'}',
              style: const TextStyle(color: Color(0xFF22D3EE),
                fontWeight: FontWeight.w900, fontSize: 14)),
          ]),
          Row(children: [
            _headerBadge('DN${_diametre.toInt()}',
              const Color(0xFF22D3EE)),
            const SizedBox(width: 6),
            _headerBadge(resinName, Colors.white),
            const SizedBox(width: 6),
            _headerBadge('${widget.epaisseur.toStringAsFixed(2)}mm/passe',
              Colors.white),
          ]),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF22D3EE).withOpacity(0.3))),
            child: Row(children: [
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF22D3EE), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('LIVE DATA', style: TextStyle(
                color: Color(0xFF22D3EE), fontSize: 8,
                fontWeight: FontWeight.w900, letterSpacing: 1)),
            ])),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          // ── Rappel paramètres ──────────────────
          _buildParamsReminder(totalEp, resinName),
          const SizedBox(height: 14),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Colonne gauche: Séquence passes ─
            Expanded(flex: 5,
              child: _buildPassesList()),
            const SizedBox(width: 14),
            // ── Colonne droite: Puissance + Vitesse
            Expanded(flex: 7,
              child: Column(children: [
                _buildPowerPanel(),
                const SizedBox(height: 10),
                _buildSpeedPanel(),
                const SizedBox(height: 10),
                _buildToolbar(),
              ])),
          ]),
          const SizedBox(height: 14),

          // ── Données live ─────────────────────
          _buildLiveData(),
          const SizedBox(height: 20),
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
      child: Text(text, style: TextStyle(color: color,
        fontSize: 8, fontWeight: FontWeight.w900)));
  }

  // ── Rappel paramètres ─────────────────────────
  Widget _buildParamsReminder(String totalEp, String resinName) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.06))),
      child: Column(children: [
        Text('RAPPEL PARAMÈTRES', style: TextStyle(
          color: Colors.grey[500], fontSize: 8,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(children: [
          _paramCell('Diamètre',        'DN${_diametre.toInt()}'),
          _paramCell('Longueur',        '${_longueur}m'),
          _paramCell('Ép./Passe',       '${widget.epaisseur.toStringAsFixed(2)}mm'),
          _paramCell('Nb Passes',       '$_passes'),
          _paramCell('Ép. Totale',      '${totalEp}mm'),
          _paramCell('Qté/Passe',
            '${_qteParPasse.toStringAsFixed(2)}L',
            color: const Color(0xFF22D3EE)),
        ]),
      ]),
    );
  }

  Widget _paramCell(String label, String value,
      {Color color = Colors.white}) {
    return Expanded(child: Column(children: [
      Text(label, style: TextStyle(color: Colors.grey[600],
        fontSize: 7, fontWeight: FontWeight.w700,
        letterSpacing: 0.5), textAlign: TextAlign.center),
      const SizedBox(height: 3),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6)),
        child: Text(value, style: TextStyle(color: color,
          fontSize: 10, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center)),
    ]));
  }

  // ── Séquence passes ───────────────────────────
  Widget _buildPassesList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.layers, color: Colors.purple, size: 13),
          const SizedBox(width: 6),
          Text("SÉQUENCE D'INJECTION", style: TextStyle(
            color: Colors.grey[400], fontSize: 8,
            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        ...List.generate(_passes, (i) {
          final passNum   = i + 1;
          final isDone    = passNum <= _passesDone;
          final isActive  = _isRunning && _currentPass == passNum;
          Color borderColor;
          if (isDone)       borderColor = Colors.green.withOpacity(0.4);
          else if (isActive) borderColor = const Color(0xFF22D3EE);
          else               borderColor = Colors.white.withOpacity(0.06);

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                ? const Color(0xFF22D3EE).withOpacity(0.07)
                : isDone
                  ? Colors.green.withOpacity(0.05)
                  : Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor)),
            child: Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isDone
                    ? Colors.green.withOpacity(0.2)
                    : isActive
                      ? const Color(0xFF22D3EE).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle),
                child: Center(child: isDone
                  ? const Icon(Icons.check,
                      color: Colors.green, size: 12)
                  : isActive
                    ? const Icon(Icons.play_arrow,
                        color: Color(0xFF22D3EE), size: 12)
                    : Text('$passNum', style: TextStyle(
                        color: Colors.grey[500], fontSize: 9,
                        fontWeight: FontWeight.w900)))),
              const SizedBox(width: 8),
              Expanded(child: Text('Passe N°$passNum',
                style: TextStyle(
                  color: isDone ? Colors.green
                    : isActive ? Colors.white : Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w700))),
              if (isDone)
                const Icon(Icons.check_circle,
                  color: Colors.green, size: 14)
              else if (!_isRunning)
                GestureDetector(
                  onTap: () => _showSafetyModal(passNum),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(
                        color: Colors.white.withOpacity(0.2),
                        blurRadius: 6)]),
                    child: const Text('GO',
                      style: TextStyle(color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)))),
            ]),
          );
        }),
      ]),
    );
  }

  // ── Puissance pompe ───────────────────────────
  Widget _buildPowerPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.water_drop, color: Color(0xFF22D3EE), size: 13),
            const SizedBox(width: 6),
            Text('PUISSANCE POMPE', style: TextStyle(
              color: Colors.grey[400], fontSize: 8,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ]),
          Text('${_Q.toStringAsFixed(2)} L/min',
            style: const TextStyle(color: Color(0xFF22D3EE),
              fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        Row(children: [25, 50, 75, 100].map((p) {
          final isActive = _pumpPower == p;
          return Expanded(child: GestureDetector(
            onTap: () => _setPumpPower(p),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                  ? const Color(0xFF22D3EE)
                  : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                    ? const Color(0xFF22D3EE)
                    : Colors.white.withOpacity(0.1)),
                boxShadow: isActive ? [BoxShadow(
                  color: const Color(0xFF22D3EE).withOpacity(0.4),
                  blurRadius: 8)] : null),
              child: Text('$p%', textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.grey[400],
                  fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ));
        }).toList()),
        const SizedBox(height: 4),
        Text('Régulation Auto', style: TextStyle(
          color: Colors.grey[700], fontSize: 8,
          fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── Vitesse tracteur ──────────────────────────
  Widget _buildSpeedPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEAB308).withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.speed, color: Color(0xFFEAB308), size: 13),
          const SizedBox(width: 6),
          Text('VITESSE TRACTEUR', style: TextStyle(
            color: Colors.grey[400], fontSize: 8,
            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_vitesse.toStringAsFixed(2),
            style: const TextStyle(color: Color(0xFFEAB308),
              fontSize: 36, fontWeight: FontWeight.w900)),
          const Padding(
            padding: EdgeInsets.only(top: 12, left: 4),
            child: Text('m/min', style: TextStyle(
              color: Color(0xFFEAB308), fontSize: 11))),
        ]),
        Text('Allure synchronisée', style: TextStyle(
          color: Colors.grey[700], fontSize: 8,
          fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── Barre d'outils ────────────────────────────
  Widget _buildToolbar() {
    return Row(children: [
      // Reset 0
      Expanded(child: GestureDetector(
        onTap: _resetPass,
        child: _toolBtn(Icons.replay, 'Reset 0',
          Colors.grey[300]!))),
      const SizedBox(width: 6),
      // Stop
      Expanded(child: GestureDetector(
        onTap: _isRunning ? _stopPass : null,
        child: _toolBtn(Icons.stop, 'Stop', Colors.red,
          disabled: !_isRunning))),
    ]);
  }

  Widget _toolBtn(IconData icon, String label,
      Color color, {bool disabled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: disabled
          ? Colors.white.withOpacity(0.02)
          : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: disabled
            ? Colors.white.withOpacity(0.05)
            : color.withOpacity(0.3))),
      child: Column(children: [
        Icon(icon, color: disabled ? Colors.grey[700] : color,
          size: 16),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(
          color: disabled ? Colors.grey[700] : color,
          fontSize: 8, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ── Données live ──────────────────────────────
  Widget _buildLiveData() {
    final remainingMins = _vitesse > 0
      ? _metersLeft / _vitesse : 0.0;
    final totalResin = _qteParPasse * _passes;
    final resinLeft  = (totalResin - _resinConso).clamp(0, totalResin);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.06))),
      child: Column(children: [
        Text('DONNÉES LIVE', style: TextStyle(
          color: Colors.grey[500], fontSize: 8,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, childAspectRatio: 2.2,
          mainAxisSpacing: 8, crossAxisSpacing: 8,
          children: [
            _liveCell('Mètres résinés',
              '${_metersDone.toStringAsFixed(2)} m',
              const Color(0xFF22D3EE)),
            _liveCell('Mètres restants',
              '${_metersLeft.toStringAsFixed(2)} m',
              Colors.white),
            _liveCell('Temps écoulé',
              _fmt(_timeElapsed), Colors.white),
            _liveCell('Temps restant',
              _fmt(remainingMins.toDouble()), Colors.white),
            _liveCell('Résine consommée',
              '${_resinConso.toStringAsFixed(2)} L',
              Colors.purple),
            _liveCell('Résine restante',
              '${resinLeft.toStringAsFixed(2)} L',
              Colors.white),
          ],
        ),
      ]),
    );
  }

  Widget _liveCell(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.grey[500],
          fontSize: 8, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(value, style: TextStyle(color: color,
          fontSize: 16, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}
