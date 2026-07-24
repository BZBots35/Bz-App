import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Écran de test/debug : affiche en direct les données brutes que la Pi
/// reçoit de l'Arduino via /telemetry. Pas de logique métier, juste de
/// l'observation pour valider que la chaîne Arduino → Pi → Flutter fonctionne.
class PumpDebugScreen extends StatefulWidget {
  final String piBase;

  const PumpDebugScreen({super.key, required this.piBase});

  @override
  State<PumpDebugScreen> createState() => _PumpDebugScreenState();
}

class _PumpDebugScreenState extends State<PumpDebugScreen> {
  Timer? _timer;

  bool _piReachable = false;
  String _rawJson = '—';
  bool _arduinoConnected = false;
  DateTime? _lastFetch;
  String? _lastError;

  // ── Champs de télémétrie (structure bz_app_fusion.ino) ──
  int _etat = -1;
  double _charge1 = 0.0;
  double _charge2 = 0.0;
  double _debit1 = 0.0;
  double _debit2 = 0.0;
  double _vitesse4 = 0.0;
  double? _tempPR;
  double? _tempPD;
  double? _tempRR;
  double? _tempRD;
  int _niveauResine = 0;
  int _niveauDurcisseur = 0;

  static const List<String> _etatLabels = [
    'DEFAUT',
    'INIT_POMPE',
    'ASP_M1',
    'REF_M1',
    'ATTENTE_ROTATION',
    'ROT_VERS_C3',
    'ROT_VERS_C4',
  ];

  String get _etatLabel =>
      (_etat >= 0 && _etat < _etatLabels.length) ? _etatLabels[_etat] : '—';

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final resp = await http
          .get(Uri.parse('${widget.piBase}/telemetry'))
          .timeout(const Duration(seconds: 2));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        setState(() {
          _piReachable = true;
          _lastError = null;
          _lastFetch = DateTime.now();
          _rawJson = const JsonEncoder.withIndent('  ').convert(data);

          _etat = (data['etat'] as num?)?.toInt() ?? -1;
          _charge1 = (data['charge1'] as num?)?.toDouble() ?? 0.0;
          _charge2 = (data['charge2'] as num?)?.toDouble() ?? 0.0;
          _debit1 = (data['debit1'] as num?)?.toDouble() ?? 0.0;
          _debit2 = (data['debit2'] as num?)?.toDouble() ?? 0.0;
          _vitesse4 = (data['vitesse4'] as num?)?.toDouble() ?? 0.0;
          _tempPR = (data['temp_PR'] as num?)?.toDouble();
          _tempPD = (data['temp_PD'] as num?)?.toDouble();
          _tempRR = (data['temp_RR'] as num?)?.toDouble();
          _tempRD = (data['temp_RD'] as num?)?.toDouble();
          _niveauResine = (data['niveau_resine'] as num?)?.toInt() ?? 0;
          _niveauDurcisseur =
              (data['niveau_durcisseur'] as num?)?.toInt() ?? 0;
          _arduinoConnected = data['connected'] == true;
        });
      } else {
        setState(() {
          _piReachable = false;
          _lastError = 'HTTP ${resp.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _piReachable = false;
        _lastError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('DEBUG — ARDUINO ↔ PI',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetch,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _statusBadge(),
          const SizedBox(height: 16),

          _sectionTitle('CYCLE'),
          const SizedBox(height: 8),
          _valueTile('État machine', '$_etatLabel ($_etat)', Colors.amber),
          const SizedBox(height: 16),

          _sectionTitle('DÉBITS'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _valueTile('Débit 1', '${_debit1.toStringAsFixed(3)} L/min',
                    Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _valueTile('Débit 2', '${_debit2.toStringAsFixed(3)} L/min',
                    const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 8),
          _valueTile('Vitesse 4', '${_vitesse4.toStringAsFixed(3)} L/min',
              Colors.tealAccent),
          const SizedBox(height: 16),

          _sectionTitle('CHARGES MOTEUR (courant)'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _valueTile('Charge 1',
                    '${_charge1.toStringAsFixed(1)} %', Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _valueTile('Charge 2',
                    '${_charge2.toStringAsFixed(1)} %', const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 16),

          _sectionTitle('TEMPÉRATURES (PT100)'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _tempTile('Résine (pompe)', _tempPR, Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(child: _tempTile('Durcisseur (pompe)', _tempPD, const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _tempTile('Résine (réservoir)', _tempRR, Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(child: _tempTile('Durcisseur (réservoir)', _tempRD, const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 16),

          _sectionTitle('NIVEAUX RÉSERVOIRS'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _valueTile('Niveau résine',
                    _niveauResine == 1 ? 'BAS ⚠️' : 'OK',
                    _niveauResine == 1 ? Colors.redAccent : Colors.greenAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _valueTile('Niveau durcisseur',
                    _niveauDurcisseur == 1 ? 'BAS ⚠️' : 'OK',
                    _niveauDurcisseur == 1 ? Colors.redAccent : Colors.greenAccent)),
          ]),
          const SizedBox(height: 16),

          _valueTile('Arduino → Pi frais', _arduinoConnected ? 'OUI' : 'NON',
              _arduinoConnected ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            _lastFetch != null
                ? 'Dernière réponse : ${_lastFetch!.hour.toString().padLeft(2, '0')}:${_lastFetch!.minute.toString().padLeft(2, '0')}:${_lastFetch!.second.toString().padLeft(2, '0')}'
                : 'Aucune réponse reçue pour le moment',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 4),
            Text('Erreur : $_lastError',
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ],
          const SizedBox(height: 20),
          Text('JSON BRUT REÇU DE /telemetry',
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12)),
            child: Text(
              _rawJson,
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: TextStyle(
            color: Colors.grey[500],
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5));
  }

  Widget _statusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: _piReachable
              ? Colors.green.withOpacity(0.12)
              : Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _piReachable
                  ? Colors.green.withOpacity(0.4)
                  : Colors.red.withOpacity(0.4))),
      child: Row(children: [
        Icon(
          _piReachable ? Icons.check_circle : Icons.error,
          color: _piReachable ? Colors.greenAccent : Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          _piReachable ? 'PI JOIGNABLE (${widget.piBase})' : 'PI INJOIGNABLE',
          style: TextStyle(
              color: _piReachable ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w900,
              fontSize: 12),
        ),
      ]),
    );
  }

  Widget _valueTile(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _tempTile(String label, double? temp, Color color) {
    return _valueTile(
        label, temp != null ? '${temp.toStringAsFixed(1)} °C' : '—', color);
  }
}