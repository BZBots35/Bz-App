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
  double _consoMoteurAPercent = 0.0;
  double _consoMoteurBPercent = 0.0;
  double _debitA = 0.0;
  double _debitB = 0.0;
  double _debit = 0.0;
  int _capteurRaw = 0;
  String _activePump = '—';
  bool _arduinoConnected = false;
  DateTime? _lastFetch;
  String? _lastError;

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
          _consoMoteurAPercent =
              ((data['consoMoteurA_percent'] as num?)?.toDouble() ?? 0.0)
                  .clamp(0.0, 100.0);
          _consoMoteurBPercent =
              ((data['consoMoteurB_percent'] as num?)?.toDouble() ?? 0.0)
                  .clamp(0.0, 100.0);
          _debitA = (data['debitA'] as num?)?.toDouble() ?? 0.0;
          _debitB = (data['debitB'] as num?)?.toDouble() ?? 0.0;
          _debit = (data['debit'] as num?)?.toDouble() ?? 0.0;
          _capteurRaw = (data['capteur_raw'] as num?)?.toInt() ?? 0;
          _activePump = (data['active_pump'] as String?) ?? '—';
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

          // ── Zone de calibration CAPTEUR ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CALIBRATION CAPTEUR À FOURCHE',
                  style: TextStyle(
                      color: Colors.amber[200],
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(
                'Observe physiquement quel côté pousse pendant que tu notes '
                'la valeur ci-dessous, puis ajuste CAPTEUR_1_IS_PUMP_A dans '
                'pi_pump_server.py si besoin.',
                style: TextStyle(color: Colors.grey[400], fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _valueTile('CAPTEUR (brut)', '$_capteurRaw',
                        Colors.amber)),
                const SizedBox(width: 8),
                Expanded(
                    child: _valueTile('Pompe active', _activePump,
                        Colors.amber)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          _valueTile('Débit courant (poussé)', '${_debit.toStringAsFixed(3)} L/min',
              const Color(0xFF22D3EE)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _valueTile('Débit A', '${_debitA.toStringAsFixed(3)} L/min',
                    Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _valueTile('Débit B', '${_debitB.toStringAsFixed(3)} L/min',
                    const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _valueTile('Charge A',
                    '${_consoMoteurAPercent.toStringAsFixed(1)} %', Colors.purpleAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _valueTile('Charge B',
                    '${_consoMoteurBPercent.toStringAsFixed(1)} %', const Color(0xFF22D3EE))),
          ]),
          const SizedBox(height: 8),
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
}
