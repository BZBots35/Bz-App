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

  const PumpOperationScreen({
    super.key,
    required this.canalisationDoc,
    required this.chantierDoc,
    required this.epaisseur,
    required this.resinType,
    required this.userName,
  });

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

  // ── Paramètres de la canalisation ─────────────
  late double _longueur;
  late double _diametre;
  late int _passes;
  late String _label;

  // ── État Passes & Métriques ───────────────────
  int _currentPass = 0; 
  int _passesDone = 0;
  bool _isRunning = false; 
  Timer? _timer;
  
  double _metersDone = 0;
  double _metersLeft = 0;
  double _timeElapsed = 0; 
  double _resinConso = 0;

  // ── Commandes Opérateur ─────────────
  bool _isPumpOn = false;
  double _debitCommand = 0.0; // Max 0.8 L/min
  double _vitesseCommand = 0.0; // Max 1.2 m/min

  // ── Télémétrie (Simulée) ────────────
  double _consoMoteurA = 0.0; 
  double _consoMoteurB = 0.0; 
  bool _niveauResineOk = true;
  bool _niveauDurcisseurOk = true;
  double _tempNourriceResine = 20.0; 
  double _tempNourriceDurcisseur = 20.0; 
  double _tempCouverture1 = 25.0; 
  double _tempCouverture2 = 25.0; 
  double _debitReel = 0.0; 
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _checkPiConnection();
    final d = widget.canalisationDoc.data;
    _label = d['label'] as String? ?? '';
    _longueur = double.tryParse(d['longueur'] as String? ?? '10') ?? 10;
    _diametre = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
    _passes = d['passes'] as int? ?? 4;
    _metersLeft = _longueur;
    
    _startGlobalTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _qteParPasse =>
      _longueur * (math.pi * _diametre * widget.epaisseur / 1000);

  String _fmt(double mins) {
    final m = mins.floor();
    final s = ((mins - m) * 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Timer Global (Avancement Tracteur + Télémétrie) ──
  void _startGlobalTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        if (_isPumpOn) {
          _consoMoteurA = 40.0 + (_debitCommand * 50) + _random.nextDouble() * 5;
          _consoMoteurB = 42.0 + (_debitCommand * 50) + _random.nextDouble() * 5;
          _debitReel = _debitCommand > 0 ? _debitCommand - 0.02 + (_random.nextDouble() * 0.04) : 0.0;
          if (_debitReel < 0) _debitReel = 0;
          if (_tempNourriceResine < 35.0) _tempNourriceResine += 0.05;
          if (_tempNourriceDurcisseur < 35.0) _tempNourriceDurcisseur += 0.05;
        } else {
          _consoMoteurA = 0.0;
          _consoMoteurB = 0.0;
          _debitReel = 0.0;
        }

        if (_isRunning && _isPumpOn && _vitesseCommand > 0) {
          final deltaMeters = _vitesseCommand / 60; 
          _metersDone += deltaMeters;
          _metersLeft = (_longueur - _metersDone).clamp(0, _longueur);
          _timeElapsed += 1 / 60;
          
          _resinConso = (_passesDone * _qteParPasse) +
              _metersDone * (math.pi * _diametre * widget.epaisseur / 1000);

          if (_metersLeft <= 0.001) {
            _isRunning = false;
            _isPumpOn = false;
            _passesDone++;
            _sendCmd('6'); 
            if (_passesDone >= _passes) {
              _markTermine();
            }
          }
        }
      });
    });
  }

  // ── Logique Passes ────────────────────────────
  void _startPass(int passNum) {
    if (_isRunning) return;
    setState(() {
      _currentPass = passNum;
      _isRunning = true;
      _metersDone = 0;
      _metersLeft = _longueur;
      _timeElapsed = 0;
      _resinConso = _passesDone * _qteParPasse;
    });
  }

  void _stopPass() {
    setState(() {
      _isRunning = false;
      _isPumpOn = false;
    });
    _sendCmd('6'); 
    _service.updateCanalisation(widget.canalisationDoc.$id, statut: 'en_cours');
  }

  void _resetPass() {
    setState(() {
      _metersDone = 0;
      _metersLeft = _longueur;
      _timeElapsed = 0;
      _isPumpOn = false;
    });
    _sendCmd('6');
  }

  Future<void> _markTermine() async {
    await _service.updateCanalisation(widget.canalisationDoc.$id, statut: 'termine');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Canalisation terminée !'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating));
      Navigator.pop(context);
    }
  }

  // ── Commandes Opérateur ───────────────────────
  void _togglePump() {
    if (!_isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Veuillez démarrer une passe via le bouton GO d\'abord.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() {
      _isPumpOn = !_isPumpOn;
    });
    _sendCmd(_isPumpOn ? '1' : '6'); 
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
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'Avant de démarrer la passe $passNum, vérifiez que la résine est correctement préparée et que la pompe est prête.',
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
                const Expanded(
                    child: Text('Résine prête et vérifiée',
                        style: TextStyle(color: Colors.white, fontSize: 12))),
              ]),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22D3EE),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.withOpacity(0.2)),
              child: const Text('DÉMARRER',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
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
        ? 'Spraycoat+'
        : 'Spraycoat Flex';
    final totalEp = (widget.epaisseur * _passes).toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () {
              Navigator.pop(context);
            }),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('COATING ',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
            Text('#${widget.canalisationDoc.data['label'] ?? '—'}',
                style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
          ]),
          Row(children: [
            _headerBadge('DN${_diametre.toInt()}', const Color(0xFF22D3EE)),
            const SizedBox(width: 6),
            _headerBadge(resinName, Colors.white),
            const SizedBox(width: 6),
            _headerBadge(
                '${widget.epaisseur.toStringAsFixed(2)}mm/passe', Colors.white),
          ]),
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
                        color: _piConnected ? const Color(0xFF22D3EE) : Colors.red,
                        shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_piConnected ? 'PI CONNECTÉ' : 'PI HORS LIGNE',
                    style: TextStyle(
                        color: _piConnected ? const Color(0xFF22D3EE) : Colors.red,
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

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: _buildPassesList()),
            const SizedBox(width: 14),
            Expanded(flex: 7, child: _buildOperatorCommands()),
          ]),
          const SizedBox(height: 14),

          _buildTelemetryData(),
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
        Text('RAPPEL PARAMÈTRES',
            style: TextStyle(
                color: Colors.grey[500],
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(children: [
          _paramCell('Diamètre', 'DN${_diametre.toInt()}'),
          _paramCell('Longueur', '${_longueur}m'),
          _paramCell('Ép./Passe', '${widget.epaisseur.toStringAsFixed(2)}mm'),
          _paramCell('Nb Passes', '$_passes'),
          _paramCell('Ép. Totale', '${totalEp}mm'),
          _paramCell('Qté/Passe', '${_qteParPasse.toStringAsFixed(2)}L',
              color: const Color(0xFF22D3EE)),
        ]),
      ]),
    );
  }

  Widget _paramCell(String label, String value,
      {Color color = Colors.white}) {
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
      Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6)),
          child: Text(value,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center)),
    ]));
  }

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
          Text("SÉQUENCE D'INJECTION",
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        ...List.generate(_passes, (i) {
          final passNum = i + 1;
          final isDone = passNum <= _passesDone;
          final isActive = _isRunning && _currentPass == passNum;
          Color borderColor;
          if (isDone) {
            borderColor = Colors.green.withOpacity(0.4);
          } else if (isActive) {
            borderColor = const Color(0xFF22D3EE);
          } else {
            borderColor = Colors.white.withOpacity(0.06);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green.withOpacity(0.2)
                          : isActive
                              ? const Color(0xFF22D3EE).withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle),
                  child: Center(
                      child: isDone
                          ? const Icon(Icons.check,
                              color: Colors.green, size: 12)
                          : isActive
                              ? const Icon(Icons.play_arrow,
                                  color: Color(0xFF22D3EE), size: 12)
                              : Text('$passNum',
                                  style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900)))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Passe N°$passNum',
                      style: TextStyle(
                          color: isDone
                              ? Colors.green
                              : isActive
                                  ? Colors.white
                                  : Colors.grey[400],
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
              if (isDone)
                const Icon(Icons.check_circle, color: Colors.green, size: 14)
              else if (!_isRunning)
                GestureDetector(
                    onTap: () => _showSafetyModal(passNum),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.white.withOpacity(0.2),
                                  blurRadius: 6)
                            ]),
                        child: const Text('GO',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w900)))),
            ]),
          );
        }),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: GestureDetector(
                  onTap: _resetPass,
                  child: _toolBtn(Icons.replay, 'Reset 0', Colors.grey[300]!))),
          const SizedBox(width: 6),
          Expanded(
              child: GestureDetector(
                  onTap: _isRunning ? _stopPass : null,
                  child: _toolBtn(Icons.stop, 'Stop', Colors.red,
                      disabled: !_isRunning))),
        ]),
      ]),
    );
  }

  Widget _toolBtn(IconData icon, String label, Color color,
      {bool disabled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: disabled ? Colors.white.withOpacity(0.02) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: disabled
                  ? Colors.white.withOpacity(0.05)
                  : color.withOpacity(0.3))),
      child: Column(children: [
        Icon(icon, color: disabled ? Colors.grey[700] : color, size: 16),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: disabled ? Colors.grey[700] : color,
                fontSize: 8,
                fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ── BLOC OPÉRATEUR (Inclut le Speedometer) ───────────────────────
  Widget _buildOperatorCommands() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.tune, color: Color(0xFF22D3EE), size: 13),
          const SizedBox(width: 6),
          Text('CONTRÔLES OPÉRATEUR',
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 12),
        
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isPumpOn ? Colors.red : Colors.green,
            minimumSize: const Size(double.infinity, 45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _togglePump,
          child: Text(
            _isPumpOn ? 'ARRÊTER POMPE' : 'ALLUMER POMPE',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Débit Pompe', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
          Text('${_debitCommand.toStringAsFixed(2)} L/min', style: const TextStyle(color: Color(0xFF22D3EE), fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
          ),
          child: Slider(
            value: _debitCommand,
            min: 0.0,
            max: 0.8,
            divisions: 80,
            activeColor: const Color(0xFF22D3EE),
            inactiveColor: Colors.grey[800],
            onChanged: (val) {
              setState(() => _debitCommand = val);
            },
          ),
        ),
        const Divider(color: Colors.white12, height: 16),

        SpeedometerGauge(currentSpeed: _vitesseCommand),
        const SizedBox(height: 8),

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Consigne Vitesse Tracteur', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
          Text('${_vitesseCommand.toStringAsFixed(2)} m/min', style: const TextStyle(color: Color(0xFFEAB308), fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
          ),
          child: Slider(
            value: _vitesseCommand,
            min: 0.0,
            max: 1.2,
            divisions: 120,
            activeColor: const Color(0xFFEAB308),
            inactiveColor: Colors.grey[800],
            onChanged: (val) {
              setState(() => _vitesseCommand = val);
            },
          ),
        ),
      ]),
    );
  }

  // ── LE NOUVEAU TABLEAU DE BORD "SEXY" ──────────────────────────────
  // ── LE TABLEAU DE BORD "SEXY" (AVEC CUVES 3D) ──────────────────────────────
  Widget _buildTelemetryData() {
    final totalResin = _qteParPasse * _passes;
    final resinLeft = (totalResin - _resinConso).clamp(0.0, totalResin);
    
    // NOUVEAU : Calcul du pourcentage de remplissage pour l'animation visuelle
    final double fillRatio = totalResin > 0 ? resinLeft / totalResin : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. BLOC MÈTRES & TEMPS
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06))),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 2.2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _buildMetricCard('Mètres résinés', '${_metersDone.toStringAsFixed(2)} m', const Color(0xFF22D3EE)),
              _buildMetricCard('Mètres restants', '${_metersLeft.toStringAsFixed(2)} m', Colors.white),
              _buildMetricCard('Débit Mesuré', '${_debitReel.toStringAsFixed(3)} L/m', const Color(0xFFEAB308)),
              _buildMetricCard('Temps écoulé', _fmt(_timeElapsed), Colors.white),
              _buildMetricCard('Résine Conso.', '${_resinConso.toStringAsFixed(2)} L', Colors.purpleAccent),
              _buildMetricCard('Résine Reste', '${resinLeft.toStringAsFixed(2)} L', Colors.white),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. BLOC HARDWARE VIP
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF101015),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF22D3EE).withOpacity(0.03),
                    blurRadius: 15,
                    spreadRadius: 2)
              ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.memory, color: Color(0xFF22D3EE), size: 16),
                const SizedBox(width: 8),
                Text('SUPERVISION HARDWARE',
                    style: TextStyle(
                        color: Colors.cyan[100],
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
              ]),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white12, height: 1),
              ),

              // Jauges Moteurs
              _buildMotorGauge('EFFORT MOTEUR POMPE A', _consoMoteurA),
              const SizedBox(height: 12),
              _buildMotorGauge('EFFORT MOTEUR POMPE B', _consoMoteurB),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white12, height: 1),
              ),

              // Thermomètres & Réservoirs
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Colonne Températures
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _buildTempBadge('Nourrice Résine', _tempNourriceResine)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTempBadge('Nourrice Durcis.', _tempNourriceDurcisseur)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _buildTempBadge('Couverture 1', _tempCouverture1)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTempBadge('Couverture 2', _tempCouverture2)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Colonne Réservoirs (Les nouvelles cuves !)
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(child: TankLevelGauge(label: 'RÉSINE', fillRatio: fillRatio, color: Colors.purpleAccent, isSensorOk: _niveauResineOk)),
                        const SizedBox(width: 8),
                        Expanded(child: TankLevelGauge(label: 'DURCIS.', fillRatio: fillRatio, color: const Color(0xFF22D3EE), isSensorOk: _niveauDurcisseurOk)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- WIDGETS VISUELS ---

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.1))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 8, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
    );
  }

  Widget _buildMotorGauge(String label, double percent) {
    Color barColor = percent > 80.0 ? Colors.redAccent : percent > 60.0 ? Colors.orangeAccent : Colors.greenAccent;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            Text('${percent.toInt()}%', style: TextStyle(color: barColor, fontSize: 12, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: Colors.white.withOpacity(0.05),
            color: barColor,
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTempBadge(String label, double temp) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(Icons.thermostat, color: Colors.orange[400], size: 16),
          const SizedBox(height: 4),
          Text('${temp.toStringAsFixed(1)}°C', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 7, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildTankStatus(String label, bool isOk, Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isOk ? themeColor.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isOk ? themeColor.withOpacity(0.3) : Colors.red.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOk ? Icons.water_drop : Icons.water_drop_outlined, 
            color: isOk ? themeColor : Colors.redAccent, 
            size: 28
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isOk ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4)
            ),
            child: Text(
              isOk ? 'OK' : 'VIDE', 
              style: TextStyle(color: isOk ? Colors.greenAccent : Colors.redAccent, fontSize: 8, fontWeight: FontWeight.w900)
            ),
          )
        ],
      ),
    );
  }
} // <-- FIN DE LA CLASSE PRINCIPALE

// =========================================================
// CLASSES EXTERNES (LE COMPTEUR DE VITESSE)
// =========================================================

class SpeedometerGauge extends StatelessWidget {
  final double currentSpeed;
  final double maxSpeed;

  const SpeedometerGauge({
    super.key, 
    required this.currentSpeed, 
    this.maxSpeed = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      child: CustomPaint(
        painter: _SpeedometerPainter(currentSpeed, maxSpeed),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 25), 
              Text(
                currentSpeed.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 20, 
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'm/min',
                style: TextStyle(
                  color: Colors.grey, 
                  fontSize: 9, 
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  _SpeedometerPainter(this.speed, this.maxSpeed);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final startAngle = math.pi * 0.75; 
    final sweepAngle = math.pi * 1.5;  

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    final activePaint = Paint()
      ..color = const Color(0xFFEAB308)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final progressRatio = (speed / maxSpeed).clamp(0.0, 1.0);
    final progressAngle = progressRatio * sweepAngle;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle,
      progressAngle,
      false,
      activePaint,
    );

    final needlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final currentAngle = startAngle + progressAngle;
    final needleLength = radius - 18; 
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(currentAngle),
      center.dy + needleLength * math.sin(currentAngle),
    );
    canvas.drawLine(center, needleEnd, needlePaint);

    final pinPaint = Paint()..color = const Color(0xFFEAB308);
    canvas.drawCircle(center, 4, pinPaint);
    canvas.drawCircle(center, 2, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed;
  }
}
class TankLevelGauge extends StatelessWidget {
  final String label;
  final double fillRatio; // Valeur de 0.0 à 1.0
  final Color color;
  final bool isSensorOk;

  const TankLevelGauge({
    super.key,
    required this.label,
    required this.fillRatio,
    required this.color,
    required this.isSensorOk,
  });

  @override
  Widget build(BuildContext context) {
    // Si le capteur physique détecte une cuve vide, on force la jauge à 0 et on passe en rouge.
    final displayRatio = isSensorOk ? fillRatio.clamp(0.0, 1.0) : 0.0;
    final themeColor = isSensorOk ? color : Colors.redAccent;

    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          height: 120, // Hauteur de la cuve
          width: 55,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              // Halo lumineux autour de la cuve
              BoxShadow(color: themeColor.withOpacity(0.15), blurRadius: 10, spreadRadius: 1)
            ]
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 1. Le Liquide (qui monte et descend)
                FractionallySizedBox(
                  heightFactor: displayRatio,
                  widthFactor: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [themeColor.withOpacity(0.6), themeColor],
                      ),
                    ),
                    // Ligne de flottaison (petit trait blanc en haut du liquide)
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(height: 2, color: Colors.white54),
                    ),
                  ),
                ),
                // 2. Reflet de vitre 3D (pour le fameux côté sexy)
                Positioned(
                  left: 4, top: 4, bottom: 4,
                  width: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // 3. Pourcentage au centre
                Center(
                  child: isSensorOk 
                    ? Text('${(displayRatio * 100).toInt()}%', 
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black, blurRadius: 4)]))
                    : const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Statut du capteur matériel sous la cuve
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isSensorOk ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4)
          ),
          child: Text(
            isSensorOk ? 'OK' : 'VIDE', 
            style: TextStyle(color: isSensorOk ? Colors.greenAccent : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.w900)
          ),
        )
      ],
    );
  }
}