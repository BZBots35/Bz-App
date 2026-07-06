// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';
import 'pump_control_screen.dart';

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

  // ── État Passes ───────────────────────────────
  int _passesDone = 0;

  double get _qteParPasse =>
      _longueur * (math.pi * _diametre * widget.epaisseur / 1000);

  @override
  void initState() {
    super.initState();
    _checkPiConnection();
    final d = widget.canalisationDoc.data;
    _label    = d['label']    as String? ?? '';
    _longueur = double.tryParse(d['longueur'] as String? ?? '10') ?? 10;
    _diametre = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
    _passes   = d['passes']   as int? ?? 4;
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

    if (confirm == true && mounted) {
      // Naviguer vers le dashboard de contrôle pour cette passe
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PumpControlScreen(
            canalisationDoc: widget.canalisationDoc,
            chantierDoc:     widget.chantierDoc,
            epaisseur:       widget.epaisseur,
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
        if (_passesDone >= _passes) {
          await _service.updateCanalisation(
            widget.canalisationDoc.$id,
            statut: 'termine',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✓ Canalisation terminée !'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating));
            Navigator.pop(context);
          }
        } else {
          await _service.updateCanalisation(
            widget.canalisationDoc.$id,
            statut: 'en_cours',
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
    final totalEp = (widget.epaisseur * _passes).toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
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
          _buildParamsReminder(totalEp, resinName),
          const SizedBox(height: 14),
          _buildPassesList(),
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
          _paramCell('Diamètre',   'DN${_diametre.toInt()}'),
          _paramCell('Longueur',   '${_longueur}m'),
          _paramCell('Ép./Passe',  '${widget.epaisseur.toStringAsFixed(2)}mm'),
          _paramCell('Nb Passes',  '$_passes'),
          _paramCell('Ép. Totale', '${totalEp}mm'),
          _paramCell('Qté/Passe',  '${_qteParPasse.toStringAsFixed(2)}L',
              color: const Color(0xFF22D3EE)),
        ]),
      ]),
    );
  }

  Widget _paramCell(String label, String value, {Color color = Colors.white}) {
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
          final isDone  = passNum <= _passesDone;
          // Une passe est disponible si c'est la prochaine à faire
          final isNext  = passNum == _passesDone + 1;

          Color borderColor;
          if (isDone)       borderColor = Colors.green.withOpacity(0.4);
          else if (isNext)  borderColor = const Color(0xFF22D3EE).withOpacity(0.4);
          else              borderColor = Colors.white.withOpacity(0.06);

          return Container(
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
                  child: Text('Passe N°$passNum',
                      style: TextStyle(
                          color: isDone
                              ? Colors.green
                              : isNext
                                  ? Colors.white
                                  : Colors.grey[600],
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
              if (isDone)
                const Icon(Icons.check_circle, color: Colors.green, size: 14)
              else if (isNext)
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
                        child: const Text('GO',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w900))))
              else
                // Passes futures verrouillées
                const Icon(Icons.lock_outline,
                    color: Colors.white24, size: 14),
            ]),
          );
        }),
      ]),
    );
  }
}
