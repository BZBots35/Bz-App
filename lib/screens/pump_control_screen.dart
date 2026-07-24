// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:fl_chart/fl_chart.dart';
import 'pump_debug_screen.dart';
import '../services/lang_service.dart';
import '../services/pump_service.dart';

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

class _PumpControlScreenState extends State<PumpControlScreen>
    with SingleTickerProviderStateMixin {

  final _lang = LangService();
  final _pumpService = PumpService();

  // ── Connexion Pi ──────────────────────────────
  bool _piConnected = false;

  Future<void> _sendCmd(String cmd) async {
    // 1. URL construite proprement
    final url = Uri.parse('${widget.piBase}/command');
    
    try {
      // 2. On envoie la commande avec le bon Header Content-Type
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
        },
        body: json.encode({"cmd": cmd}),
      );

      // 3. Debug : Si ça ne marche pas, tu verras l'erreur dans la console
      if (response.statusCode == 200) {
        print("Commande envoyée avec succès : $cmd");
      } else {
        print("Erreur serveur ${response.statusCode} : ${response.body}");
      }
    } catch (e) {
      // 4. Si le téléphone ne trouve pas le Pi, c'est ici que ça s'affiche
      print("Erreur de connexion (Check l'IP piBase) : $e");
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

  // ── Télémétrie réelle (Arduino -> Pi -> App) ────────────
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

          // Charges moteurs (courant) — Moteur A = moteur 1, Moteur B = moteur 2
          _consoMoteurA = (data['charge1'] as num?)?.toDouble() ?? _consoMoteurA;
          _consoMoteurB = (data['charge2'] as num?)?.toDouble() ?? _consoMoteurB;

          // Débit consolidé (déjà calculé côté Arduino selon aspiration/refoulement)
          _debitReel = (data['debit'] as num?)?.toDouble() ?? _debitReel;
          _vitesse4Reel = (data['vitesse4'] as num?)?.toDouble() ?? _vitesse4Reel;

          // Températures "Couverture" (affichées à côté des cuves) = capteurs réservoir
          _tempCouverture1 = (data['temp_RR'] as num?)?.toDouble() ?? _tempCouverture1;
          _tempCouverture2 = (data['temp_RD'] as num?)?.toDouble() ?? _tempCouverture2;

          // Températures "Nourrice" (affichées dans le bloc pompe) = capteurs pompe
          _tempNourriceResine = (data['temp_PR'] as num?)?.toDouble() ?? _tempNourriceResine;
          _tempNourriceDurcisseur = (data['temp_PD'] as num?)?.toDouble() ?? _tempNourriceDurcisseur;

          // Niveaux réservoirs — dans le JSON, 1 = niveau bas (problème), donc on inverse
          final niveauResineRaw = (data['niveau_resine'] as num?)?.toInt();
          if (niveauResineRaw != null) _niveauResineOk = niveauResineRaw == 0;
          final niveauDurcisseurRaw = (data['niveau_durcisseur'] as num?)?.toInt();
          if (niveauDurcisseurRaw != null) _niveauDurcisseurOk = niveauDurcisseurRaw == 0;
        });

        // Capteur niveau bas + pompe en marche -> avertissement avec décompte.
        // Pas besoin si la pompe est déjà à l'arrêt (rien à couper).
        if (_isPumpOn &&
            (!_niveauResineOk || !_niveauDurcisseurOk) &&
            !_lowLevelDialogOpen) {
          _showLowLevelWarning();
        }
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

  // ── Métriques avancement (suivi chantier — ne change pas quand on fait le plein) ──
  double _metersDone  = 0;
  double _metersLeft  = 0;
  double _timeElapsed = 0;
  double _resinConso  = 0;
  // Conso réelle (débit mesuré), uniquement pour CETTE passe — accumulée
  // séparément de _resinConso (qui mélange une base théorique des passes
  // précédentes avec les mesures réelles de la passe en cours), pour
  // pouvoir sauvegarder un total réel propre et fiable sur la canalisation.
  double _resinAppliedThisPass = 0;

  // ── Niveau physique des cuves (0.0 à 1.0), indépendant du suivi chantier ──
  // Se vide au fil du pompage, se remet à 1.0 uniquement via le bouton
  // "Plein" (confirmé par l'opérateur, pas par une mesure continue réelle).
  static const double _resineCapaciteL = 6.5;
  static const double _durcisseurCapaciteL = 3.25;
  static const double _ratioResine = 2 / 3;      // 2 parts résine...
  static const double _ratioDurcisseur = 1 / 3;  // ...pour 1 part durcisseur
  double _resineTankRatio = 1.0;
  double _durcisseurTankRatio = 1.0;

  // ── Popup niveau bas (capteur physique) ──
  bool _lowLevelDialogOpen = false;

  // ── Télémétrie réelle (toutes issues de l'Arduino via /telemetry) ──
  double _consoMoteurA            = 0.0;
  double _consoMoteurB            = 0.0;
  bool   _niveauResineOk          = true;
  bool   _niveauDurcisseurOk      = true;
  double _tempNourriceResine      = 20.0;
  double _tempNourriceDurcisseur  = 20.0;
  double _tempCouverture1         = 20.0;
  double _tempCouverture2         = 20.0;
  double _debitReel               = 0.0;
  double _vitesse4Reel            = 0.0;

  // ── Courbe épaisseur appliquée en fonction du métrage ──
  // Un point ajouté à chaque tick où la pompe avance réellement (vitesse
  // mesurée > 0). Épaisseur (mm) = (débit réel / vitesse réelle) x 1000
  // / (π x diamètre) — inverse de la formule de conso prévisionnelle
  // déjà utilisée ailleurs dans l'app.
  final List<FlSpot> _thicknessSamples = [];

  final _random = math.Random();
  Timer? _timer;
  Timer? _telemetryTimer;
  late AnimationController _heroAnimController;

  final TextEditingController _debitFieldCtrl = TextEditingController();
  final TextEditingController _vitesseFieldCtrl = TextEditingController();
  final FocusNode _debitFocus = FocusNode();
  final FocusNode _vitesseFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _metersLeft = widget.longueur;
    _resinConso = widget.passesDone * widget.qteParPasse;
    // Initialise le niveau des cuves en tenant compte de ce qui a déjà été
    // consommé sur ce chantier avant l'ouverture de l'écran (cohérent avec
    // l'ancien calcul), le suivi indépendant ne divergera qu'après un
    // premier "Plein" manuel.
    final priorVolume = widget.passesDone * widget.qteParPasse;
    _resineTankRatio = (1 - (priorVolume * _ratioResine) / _resineCapaciteL)
        .clamp(0.0, 1.0);
    _durcisseurTankRatio =
        (1 - (priorVolume * _ratioDurcisseur) / _durcisseurCapaciteL)
            .clamp(0.0, 1.0);
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
    // Animation continue (pulsation du cadre + glissement de la brillance
    // sur la barre) — tourne en permanence, seule l'opacité/le rendu dans
    // build() dépend de _isPumpOn pour l'afficher ou non.
    _heroAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _telemetryTimer?.cancel();
    _debitFieldCtrl.dispose();
    _vitesseFieldCtrl.dispose();
    _debitFocus.dispose();
    _vitesseFocus.dispose();
    _heroAnimController.dispose();
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
    if (_isPumpOn) _sendCmd('SPEED12=${_debitToPwmPercent()}');
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
        // Note : toutes les valeurs de télémétrie (charges, débit, températures,
        // niveaux) viennent désormais de _fetchTelemetry() en temps réel.
        // Ce timer ne gère plus que l'avancement du tracteur.

        // ── Avancement tracteur — basé sur la vitesse RÉELLE mesurée ──
        // (pas la consigne : si la pompe n'avance pas vraiment à la
        // vitesse demandée, la barre de progression doit le refléter)
        if (_isPumpOn && _vitesse4Reel > 0) {
          final delta = _vitesse4Reel / 60; // 1 seconde → m
          _metersDone += delta;
          _metersLeft  = (widget.longueur - _metersDone).clamp(0, widget.longueur);
          _timeElapsed += 1 / 60;
          // Conso résine = accumulation du débit RÉEL mesuré (pas la
          // consigne, pas une formule théorique sur l'épaisseur cible).
          _resinConso += _debitReel / 60;
          _resinAppliedThisPass += _debitReel / 60;

          // ── Niveau des cuves : déplétion indépendante (ratio 2:1) ──
          final volumeDeltaMixed =
              delta * (math.pi * widget.diametre * widget.epaisseur / 1000);
          _resineTankRatio = (_resineTankRatio -
                  (volumeDeltaMixed * _ratioResine) / _resineCapaciteL)
              .clamp(0.0, 1.0);
          _durcisseurTankRatio = (_durcisseurTankRatio -
                  (volumeDeltaMixed * _ratioDurcisseur) / _durcisseurCapaciteL)
              .clamp(0.0, 1.0);

          // ── Échantillon pour la courbe épaisseur/métrage ──
          // Basé sur les mesures RÉELLES (débit et vitesse mesurés), pas
          // sur la consigne — on ignore si la vitesse mesurée est ~nulle
          // pour éviter une division par zéro / valeur aberrante.
          if (_vitesse4Reel > 0.01) {
            final epaisseurInstant = double.parse(
                ((_debitReel / _vitesse4Reel) * 1000 / (math.pi * widget.diametre))
                    .toStringAsFixed(2));
            _thicknessSamples.add(FlSpot(_metersDone, epaisseurInstant));
          }

          // Passe terminée automatiquement
          if (_metersLeft <= 0.001) {
            _isPumpOn = false;
            _sendCmd('SPEED12=0');
            _timer?.cancel();
            _savePassCurve();
            _saveRealResinTotal();
            _showPasseTermineeDialog();
          }
        }
      });
    });
  }

 void _togglePump() {
  // Impossible de démarrer si la pompe n'est pas connectée — Pi joignable
  // ET Arduino qui transmet des données fraîches. (L'arrêt, lui, reste
  // toujours possible, au cas où on aurait besoin de couper malgré tout.)
  if (!_isPumpOn && (!_piConnected || !_arduinoConnected)) {
    final message = !_piConnected
        ? 'Pi injoignable — vérifie la connexion réseau.'
        : 'Arduino déconnecté — vérifie la liaison série Pi ↔ Arduino.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent.withOpacity(0.9)),
    );
    return;
  }

  // Impossible de démarrer si un niveau est bas — il faut remplir avant.
  // (L'arrêt, lui, reste toujours possible, peu importe les niveaux.)
  if (!_isPumpOn && (!_niveauResineOk || !_niveauDurcisseurOk)) {
    final resineLow = !_niveauResineOk;
    final durcisseurLow = !_niveauDurcisseurOk;
    final message = resineLow && durcisseurLow
        ? 'Niveaux résine et durcisseur bas — remplis avant de démarrer.'
        : resineLow
            ? 'Niveau résine bas — remplis avant de démarrer.'
            : 'Niveau durcisseur bas — remplis avant de démarrer.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent.withOpacity(0.9)),
    );
    return;
  }

  setState(() => _isPumpOn = !_isPumpOn);
  
  if (_isPumpOn) {
    // 1. On envoie l'ordre de démarrage (START)
    _sendCmd('START');
    // 2. On envoie la vitesse juste après (si le serveur gère le délai)
    Future.delayed(const Duration(milliseconds: 100), () {
       _sendCmd('SPEED12=${_debitToPwmPercent()}');
    });
  } else {
    // 1. On envoie l'ordre d'arrêt (STOP)
    _sendCmd('STOP');
  }
}
  String _fmt(double mins) {
    final m = mins.floor();
    final s = ((mins - m) * 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Dialog fin de passe ───────────────────────
  // Lisse une série de points par moyenne glissante (fenêtre de "window"
  // échantillons centrée sur chaque point) — évite une courbe en dents de
  // scie due au bruit naturel des mesures de débit/vitesse en temps réel.
  List<FlSpot> _smoothedSpots(List<FlSpot> raw, {int window = 7}) {
    if (raw.length <= window) return raw;
    final half = window ~/ 2;
    final result = <FlSpot>[];
    for (int i = 0; i < raw.length; i++) {
      final start = (i - half).clamp(0, raw.length - 1);
      final end = (i + half).clamp(0, raw.length - 1);
      double sum = 0;
      for (int j = start; j <= end; j++) {
        sum += raw[j].y;
      }
      result.add(FlSpot(raw[i].x, sum / (end - start + 1)));
    }
    return result;
  }

  // Ajoute un point de départ à 0m, copie de la première valeur mesurée —
  // sinon la courbe démarre au premier échantillon réel (souvent > 0m) et
  // laisse un trou visuel avant. Fait une seule fois ici : le popup de fin
  // de passe, la reconsultation et le PDF en bénéficient tous, puisque
  // ces deux derniers lisent les données déjà enregistrées (voir
  // _downsampleForStorage juste en dessous).
  List<FlSpot> _withZeroStart(List<FlSpot> spots) {
    if (spots.isEmpty || spots.first.x <= 0.001) return spots;
    return [FlSpot(0, spots.first.y), ...spots];
  }

  // Sous-échantillonne la courbe lissée pour un stockage léger : au moins
  // 30 points, et au moins 1 point tous les 0,1 m (le plus exigeant des
  // deux gagne, donc une longue canalisation aura plus que 30 points).
  List<List<double>> _downsampleForStorage() {
    final smoothed = _withZeroStart(_smoothedSpots(_thicknessSamples));
    if (smoothed.length < 2) return [];

    final target = math.max(30, (widget.longueur / 0.1).ceil());
    if (smoothed.length <= target) {
      return smoothed
          .map((s) => [
                double.parse(s.x.toStringAsFixed(2)),
                double.parse(s.y.toStringAsFixed(2)),
              ])
          .toList();
    }

    final minX = smoothed.first.x;
    final maxX = smoothed.last.x;
    final result = <List<double>>[];
    for (int i = 0; i < target; i++) {
      final targetX = minX + (maxX - minX) * i / (target - 1);
      FlSpot closest = smoothed.first;
      double bestDist = double.infinity;
      for (final s in smoothed) {
        final dist = (s.x - targetX).abs();
        if (dist < bestDist) {
          bestDist = dist;
          closest = s;
        }
      }
      result.add([
        double.parse(targetX.toStringAsFixed(2)),
        double.parse(closest.y.toStringAsFixed(2)),
      ]);
    }
    return result;
  }

  // Sauvegarde la courbe de cette passe sur la canalisation (Appwrite),
  // fusionnée avec celles des autres passes déjà enregistrées. Non
  // bloquant pour l'utilisateur si ça échoue (le PumpService gère déjà
  // la mise en file d'attente hors-ligne, et une courbe manquante n'est
  // pas critique — on ne bloque jamais la fin de la passe pour ça).
  Future<void> _savePassCurve() async {
    final points = _downsampleForStorage();
    if (points.isEmpty) return;
    try {
      Map<String, dynamic> passesData = {};
      final raw = widget.canalisationDoc.data['passesData'] as String?;
      if (raw != null && raw.isNotEmpty) {
        passesData = Map<String, dynamic>.from(json.decode(raw));
      }
      passesData['${widget.passNum}'] = points;
      await _pumpService.updateCanalisation(
        widget.canalisationDoc.$id,
        passesData: json.encode(passesData),
      );
    } catch (_) {
      // Échec silencieux volontaire — voir commentaire ci-dessus.
    }
  }

  // Sauvegarde le total RÉEL de résine consommée (basé sur le débit
  // mesuré), cumulé avec les passes précédentes déjà enregistrées sur
  // la canalisation — pour que le rapport PDF puisse comparer le réel
  // au théorique plutôt que d'afficher uniquement une estimation.
  Future<void> _saveRealResinTotal() async {
    if (_resinAppliedThisPass <= 0) return;
    try {
      final previousRaw = widget.canalisationDoc.data['resinAppliedTotal'];
      final previousTotal =
          previousRaw != null ? (previousRaw as num).toDouble() : 0.0;
      await _pumpService.updateCanalisation(
        widget.canalisationDoc.$id,
        resinAppliedTotal: previousTotal + _resinAppliedThisPass,
      );
    } catch (_) {
      // Échec silencieux volontaire, même logique que _savePassCurve.
    }
  }

  Future<void> _showPasseTermineeDialog() async {
    final smoothed = _withZeroStart(_smoothedSpots(_thicknessSamples));
    final hasData = smoothed.length >= 2;
    final maxX = hasData ? smoothed.last.x : 1.0;
    final targetEpaisseur = widget.epaisseur;
    final maxDataY = hasData
        ? smoothed.map((s) => s.y).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final maxY = (maxDataY > targetEpaisseur ? maxDataY : targetEpaisseur) * 1.2;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.green.withOpacity(0.5), width: 1)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 22),
          const SizedBox(width: 8),
          Text(_lang.t('pumpPassCompleteTitle'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                '${_lang.t('pumpPassCompletePrefix')}${widget.passNum}'
                '${_lang.t('pumpPassCompleteSuffix')}\n'
                '${_metersDone.toStringAsFixed(2)} ${_lang.t('pumpMetersResinedIn')} '
                '${_fmt(_timeElapsed)}.',
                style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 16),
              if (hasData) ...[
                Text('ÉPAISSEUR APPLIQUÉE / MÉTRAGE',
                    style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (v, meta) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${v.toStringAsFixed(1).replaceAll('.', ',')}m',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                            ),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(1)}',
                                style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.white.withOpacity(0.08))),
                      extraLinesData: ExtraLinesData(horizontalLines: [
                        HorizontalLine(
                          y: targetEpaisseur,
                          color: Colors.grey[400]!.withOpacity(0.6),
                          strokeWidth: 1,
                          dashArray: [4, 3],
                          label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              style: TextStyle(color: Colors.grey[400], fontSize: 8),
                              labelResolver: (line) => 'Cible ${targetEpaisseur.toStringAsFixed(1)}mm'),
                        ),
                      ]),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => spots.map((s) {
                            return LineTooltipItem(
                              '${s.y.toStringAsFixed(2).replaceAll('.', ',')} mm\n'
                              '${s.x.toStringAsFixed(1).replaceAll('.', ',')} m',
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: smoothed,
                          isCurved: true,
                          curveSmoothness: 0.2,
                          color: const Color(0xFF22D3EE),
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFF22D3EE).withOpacity(0.08)),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Pas assez de données mesurées pour tracer la courbe.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ),
            ]),
          ),
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
            child: Text(_lang.t('pumpBackToPassesBtn'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
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
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Text(_lang.t('pumpExitPassTitle'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13)),
        ]),
        content: Text(
          '${_lang.t('pumpExitPassMsgPrefix')}${widget.passNum}'
          '${_lang.t('pumpExitPassMsgSuffix')}',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_lang.t('pumpContinueBtn'),
                  style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text(_lang.t('pumpQuitBtn'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      _sendCmd('SPEED12=0');
      Navigator.pop(context, false); // retour sans valider la passe
    }
  }

  // ── Popup niveau bas : décompte 30s puis arrêt automatique ──
  void _showLowLevelWarning() {
    _lowLevelDialogOpen = true;
    int secondsLeft = 30;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            // Niveau redevenu OK entre-temps (capteur physique) -> on annule tout
            if (_niveauResineOk && _niveauDurcisseurOk) {
              t.cancel();
              _lowLevelDialogOpen = false;
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              return;
            }
            secondsLeft--;
            if (secondsLeft <= 0) {
              t.cancel();
              _sendCmd('STOP');
              if (mounted) setState(() => _isPumpOn = false);
              _lowLevelDialogOpen = false;
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            } else {
              setDialogState(() {});
            }
          });

          final resineLow = !_niveauResineOk;
          final durcisseurLow = !_niveauDurcisseurOk;
          final message = resineLow && durcisseurLow
              ? 'Les niveaux de résine ET de durcisseur sont bas.'
              : resineLow
                  ? 'Le niveau de résine est bas.'
                  : 'Le niveau de durcisseur est bas.';

          return AlertDialog(
            backgroundColor: const Color(0xFF0D0D0D),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1)),
            title: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              const SizedBox(width: 8),
              const Text('Niveau bas',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(message,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
              const SizedBox(height: 4),
              Text('Remplis les réservoirs maintenant.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
              const SizedBox(height: 18),
              Text('$secondsLeft s',
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 36, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('avant arrêt automatique de la pompe',
                  style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            ]),
            actions: [
              ElevatedButton(
                onPressed: () {
                  countdownTimer?.cancel();
                  _sendCmd('STOP');
                  if (mounted) setState(() => _isPumpOn = false);
                  _lowLevelDialogOpen = false;
                  Navigator.of(dialogContext).pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Arrêter maintenant',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          );
        });
      },
    ).then((_) {
      countdownTimer?.cancel();
      _lowLevelDialogOpen = false;
    });
  }

  // ── Confirmation "Plein" — remet le niveau d'une cuve à 100% ──
  Future<void> _confirmRefill(String label, VoidCallback onConfirm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.greenAccent.withOpacity(0.4))),
        title: Row(children: [
          const Icon(Icons.local_gas_station_outlined, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 8),
          Text('Plein $label',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
        content: Text(
          'Confirmer que le fût de $label vient d\'être rempli ?',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annuler', style: TextStyle(color: Colors.grey[400]))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirmer',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
    if (confirm == true) onConfirm();
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
            Text('${_lang.t('pumpPassLabel')} ',
                style: const TextStyle(
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
            tooltip: _lang.t('pumpDebugTooltip'),
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
                Text(_piConnected
                        ? _lang.t('pumpPiConnected')
                        : _lang.t('pumpPiOffline'),
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

          // ── Métriques (débit réel + réservoirs) ──
          _buildMetrics(),
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
        _vitesse4Reel > 0 ? _metersLeft / _vitesse4Reel : 0.0;

    return AnimatedBuilder(
      animation: _heroAnimController,
      builder: (context, child) {
        // Pulsation douce du cadre quand la pompe tourne (va-et-vient 0->1->0)
        final pulse = _isPumpOn
            ? (0.5 + 0.5 * math.sin(_heroAnimController.value * 2 * math.pi))
            : 0.0;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A0A0F),
                _isPumpOn
                    ? const Color(0xFF0D1A20)
                    : const Color(0xFF0A0A0F),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                width: _isPumpOn ? 1.4 : 1,
                color: _isPumpOn
                    ? const Color(0xFF22D3EE).withOpacity(0.35 + 0.25 * pulse)
                    : Colors.white.withOpacity(0.06)),
            boxShadow: _isPumpOn
                ? [
                    BoxShadow(
                        color: const Color(0xFF22D3EE)
                            .withOpacity(0.10 + 0.12 * pulse),
                        blurRadius: 22,
                        spreadRadius: 1),
                  ]
                : [],
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── En-tête : repère de passe (discret) + statut ──
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${_lang.t('pumpProgressTitlePrefix')}${widget.passNum}'
                    '${_lang.t('pumpProgressTitleSuffix')}',
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5)),
            Row(children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: _isPumpOn ? const Color(0xFF22D3EE) : Colors.grey[700],
                      shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(_isPumpOn ? 'EN COURS' : 'À L\'ARRÊT',
                  style: TextStyle(
                      color: _isPumpOn ? const Color(0xFF22D3EE) : Colors.grey[600],
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ]),
          ]),
          const SizedBox(height: 4),

          // ── Gros pourcentage, en vedette ──
          Text('${(progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                  color: Color(0xFF22D3EE),
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.0)),
          const SizedBox(height: 12),

          // ── Barre épaisse avec brillance glissante + texte incrusté ──
          LayoutBuilder(builder: (context, constraints) {
            const barHeight = 20.0;
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(children: [
                Container(
                  height: barHeight,
                  width: double.infinity,
                  color: Colors.white.withOpacity(0.05),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: barHeight,
                  width: constraints.maxWidth * progress,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isPumpOn
                          ? [const Color(0xFF0EA5C4), const Color(0xFF22D3EE)]
                          : [
                              const Color(0xFF22D3EE).withOpacity(0.35),
                              const Color(0xFF22D3EE).withOpacity(0.45)
                            ],
                    ),
                  ),
                ),
                // Brillance qui glisse — seulement quand la pompe tourne
                if (_isPumpOn && constraints.maxWidth * progress > 0)
                  Positioned.fill(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress == 0 ? 0 : progress,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Transform.translate(
                            offset: Offset(
                                -constraints.maxWidth +
                                    (_heroAnimController.value *
                                        constraints.maxWidth * 2.4),
                                0),
                            child: Container(
                              width: constraints.maxWidth * 0.28,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.0),
                                    Colors.white.withOpacity(0.35),
                                    Colors.white.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Texte incrusté : mètres résinés / total
                Positioned.fill(
                  child: Center(
                    child: Text(
                        '${_metersDone.toStringAsFixed(1).replaceAll('.', ',')} / ${widget.longueur.toStringAsFixed(1).replaceAll('.', ',')} m',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 12),

          // ── Phrase-état, lisible d'un coup d'œil ──
          Text(
              _isPumpOn
                  ? 'En cours — encore ${_fmt(remainingMins)}'
                  : 'À l\'arrêt — encore ${_fmt(remainingMins)} une fois relancé',
              style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),

          // ── Détails secondaires, en mini-cartes à icônes ──
          Row(children: [
            Expanded(
                child: _statCard(Icons.timer_outlined, 'Temps écoulé',
                    _fmt(_timeElapsed), Colors.white)),
            const SizedBox(width: 8),
            Expanded(
                child: _statCard(Icons.water_drop_outlined, 'Résine consommée',
                    '${_resinConso.toStringAsFixed(2)} L', Colors.purpleAccent)),
          ]),
        ]),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
        ),
      ]),
    );
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
          Text(_lang.t('pumpControlsTitle'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 14),

        // ── Bouton On/Off moteur ────────────────
        Builder(builder: (context) {
          final notConnected = !_piConnected || !_arduinoConnected;
          final levelLow = !_niveauResineOk || !_niveauDurcisseurOk;
          final startBlocked = !_isPumpOn && (notConnected || levelLow);
          final blockedLabel = !_isPumpOn && notConnected
              ? (!_piConnected ? 'Pi injoignable' : 'Arduino déconnecté')
              : 'Niveau bas — Remplir réservoir';
          return GestureDetector(
            onTap: _togglePump,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: startBlocked
                    ? Colors.white.withOpacity(0.03)
                    : (_isPumpOn
                        ? Colors.red.withOpacity(0.15)
                        : Colors.green.withOpacity(0.12)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: startBlocked
                        ? Colors.white.withOpacity(0.1)
                        : (_isPumpOn
                            ? Colors.red.withOpacity(0.6)
                            : Colors.green.withOpacity(0.5)),
                    width: 1.5),
                boxShadow: startBlocked
                    ? []
                    : [
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
                  startBlocked
                      ? Icons.lock_outline
                      : (_isPumpOn ? Icons.stop_circle : Icons.play_circle),
                  color: startBlocked
                      ? Colors.grey[600]
                      : (_isPumpOn ? Colors.redAccent : Colors.greenAccent),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    startBlocked
                        ? blockedLabel
                        : (_isPumpOn ? 'Arrêter pompe' : 'Démarrer pompe'),
                    style: TextStyle(
                      color: startBlocked
                          ? Colors.grey[500]
                          : (_isPumpOn ? Colors.redAccent : Colors.greenAccent),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        );
        }),
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
          Text(_lang.t('pumpSpeedControlsTitle'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Débit
          Expanded(child: Column(children: [
            Text('MESURÉ',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            SpeedometerGauge(
              currentSpeed: _debitReel,
              maxSpeed: 0.8,
              unit: 'L/min',
              color: const Color(0xFF60A5FA),
              size: 130,
            ),
            const SizedBox(height: 10),
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            const SizedBox(height: 10),
            Text('RÉGLAGE',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _debitFieldCtrl,
                focusNode: _debitFocus,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: Color(0xFF60A5FA),
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
                          color: const Color(0xFF60A5FA).withOpacity(0.3))),
                ),
                onSubmitted: _applyDebitInput,
              ),
            ),
            const SizedBox(height: 4),
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
                activeColor: const Color(0xFF60A5FA),
                inactiveColor: Colors.grey[800],
                onChanged: (val) => setState(() {
                  _debitCommand = val;
                  if (!_debitFocus.hasFocus) {
                    _debitFieldCtrl.text = val.toStringAsFixed(2);
                  }
                }),
                onChangeEnd: (val) {
                  if (_isPumpOn) _sendCmd('SPEED12=${_debitToPwmPercent()}');
                },
              ),
            ),
          ])),

          const SizedBox(width: 16),

          // Vitesse
          Expanded(child: Column(children: [
            Text('MESURÉ',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            SpeedometerGauge(currentSpeed: _vitesse4Reel, size: 130),
            const SizedBox(height: 10),
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            const SizedBox(height: 10),
            Text('RÉGLAGE',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _vitesseFieldCtrl,
                focusNode: _vitesseFocus,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: Color(0xFFD4A574),
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
                          color: const Color(0xFFD4A574).withOpacity(0.3))),
                ),
                onSubmitted: _applyVitesseInput,
              ),
            ),
            const SizedBox(height: 4),
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
                activeColor: const Color(0xFFD4A574),
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

  // ── Métriques résine & pompes ───────────────────────────
  Widget _buildMetrics() {
    return Column(children: [

      // ==========================================
      // ÉTAPE 2 : CUVES + TUYAUX CONNECTÉS
      // ==========================================
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // ── MOITIÉ GAUCHE : RÉSINE ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Puce Température — largeur fixe garantie, jamais écrasée
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 6, top: 2),
                  child: _buildCompactTempChip(
                      _lang.t('pumpCoverage1Label'),
                      _tempCouverture1,
                      Colors.purpleAccent),
                ),
                // 2. Cuve + Tuyau, centrés dans l'espace restant
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        TankLevelGauge(
                            label: _lang.t('pumpTankResinLabel'),
                            fillRatio: _resineTankRatio,
                            color: Colors.purpleAccent,
                            isSensorOk: _niveauResineOk,
                            capacityLiters: _resineCapaciteL,
                            badgeOnRight: false,
                            onRefill: () => _confirmRefill('résine',
                                () => setState(() => _resineTankRatio = 1.0))),
                        // Le tuyau soudé sous la cuve
                        Container(
                          width: 8,
                          height: 24,
                          color: Colors.purpleAccent.withOpacity(0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ── MOITIÉ DROITE : DURCISSEUR ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Cuve + Tuyau, centrés dans l'espace restant
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        TankLevelGauge(
                            label: _lang.t('pumpTankHardenerLabel'),
                            fillRatio: _durcisseurTankRatio,
                            color: const Color(0xFF22D3EE),
                            isSensorOk: _niveauDurcisseurOk,
                            capacityLiters: _durcisseurCapaciteL,
                            badgeOnRight: true,
                            onRefill: () => _confirmRefill('durcisseur',
                                () => setState(() => _durcisseurTankRatio = 1.0))),
                        // Le tuyau soudé sous la cuve
                        Container(
                          width: 8,
                          height: 24,
                          color: const Color(0xFF22D3EE).withOpacity(0.4),
                        ),
                      ],
                    ),
                  ),
                ),
                // 2. Puce Température — largeur fixe garantie, jamais écrasée
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 4, top: 2),
                  child: _buildCompactTempChip(
                      _lang.t('pumpCoverage2Label'),
                      _tempCouverture2,
                      const Color(0xFF22D3EE)),
                ),
              ],
            ),
          ),
        ],
      ),

      // ==========================================
      // ÉTAPE 3 : LE CŒUR MÉCANIQUE (BLOC POMPE)
      // ==========================================
      // (Aucun espace ici, les tuyaux viennent percuter directement le conteneur)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24), // Les tuyaux atterrissent sur cette bordure
        ),
        child: Column(
          children: [
            const Text(
              'Pompe Bz Bots',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // ── Rangée 1 : températures matière en entrée de pompe ──
            // (propriété de la résine/du durcisseur, pas du moteur — même
            // code couleur que les cuves et les puces "couverture")
            Row(
              children: [
                Expanded(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _locatedThermoIcon(Icons.arrow_circle_right_outlined,
                        Colors.purpleAccent, 17),
                    const SizedBox(width: 6),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_tempNourriceResine.toStringAsFixed(1).replaceAll('.', ',')}°C',
                          style: const TextStyle(
                              color: Colors.purpleAccent, fontSize: 14, fontWeight: FontWeight.w900)),
                      Text('Résine (entrée)',
                          style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                    ]),
                  ]),
                ),
                Expanded(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _locatedThermoIcon(Icons.arrow_circle_right_outlined,
                        const Color(0xFF22D3EE), 17),
                    const SizedBox(width: 6),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_tempNourriceDurcisseur.toStringAsFixed(1).replaceAll('.', ',')}°C',
                          style: const TextStyle(
                              color: Color(0xFF22D3EE), fontSize: 14, fontWeight: FontWeight.w900)),
                      Text('Durcisseur (entrée)',
                          style: TextStyle(color: Colors.grey[500], fontSize: 8)),
                    ]),
                  ]),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // ── Rangée 2 : charge des pompes (mécanique) ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SECTION MOTEUR A
                Expanded(
                  child: Column(
                    children: [
                      PumpLoadGauge(
                          label: 'Pompe 1',
                          percent: _consoMoteurA,
                          color: Colors.white70),
                    ],
                  ),
                ),
                
                // Ligne de séparation interne
                Container(
                  height: 100, 
                  width: 1,
                  color: Colors.white12,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),

                // SECTION MOTEUR B
                Expanded(
                  child: Column(
                    children: [
                      PumpLoadGauge(
                          label: 'Pompe 2', 
                          percent: _consoMoteurB,
                          color: Colors.white70),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  // Icône combinée : thermomètre + icône de lieu, côte à côte (pas de
  // superposition) — thermomètre = "c'est une température", icône de lieu =
  // "à cet endroit précis" (réservoir vs entrée de pompe).
  Widget _locatedThermoIcon(IconData locationIcon, Color color, double size) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.thermostat, color: color, size: size),
      SizedBox(width: size * 0.18),
      Icon(locationIcon, color: color, size: size),
    ]);
  }

  // Puce compacte température — à coller juste à côté d'une cuve (pas dessous)
  Widget _buildCompactTempChip(String label, double temp, Color color,
      {IconData locationIcon = Icons.propane_tank_outlined}) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _locatedThermoIcon(locationIcon, color, 18),
        const SizedBox(height: 6),
        Text('${temp.toStringAsFixed(1).replaceAll('.', ',')}°',
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: Colors.grey[400], fontSize: 7.5, height: 1.15)),
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
    this.color = const Color(0xFFD4A574),
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
          height: size * 0.58,
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
    // Demi-cercle "dôme" : le centre est en bas du cadre, l'arc passe par
    // le haut (180° -> 360°, sens horaire), pas de zone vide en dessous.
    final center     = Offset(size.width / 2, size.height);
    final radius     = size.width / 2 - 6;
    final startAngle = math.pi;       // 180° (gauche)
    final sweepAngle = math.pi;       // demi-tour jusqu'à 360°/0° (droite)

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
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
      Rect.fromCircle(center: center, radius: radius),
      startAngle, progress, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    final angle      = startAngle + progress;
    final needleEnd  = Offset(
      center.dx + (radius - 12) * math.cos(angle),
      center.dy + (radius - 12) * math.sin(angle),
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
  final bool badgeOnRight;
  final VoidCallback? onRefill;

  const TankLevelGauge({
    super.key,
    required this.label,
    required this.fillRatio,
    required this.color,
    required this.isSensorOk,
    required this.capacityLiters,
    this.badgeOnRight = true,
    this.onRefill,
  });

  @override
  Widget build(BuildContext context) {
    final displayRatio = isSensorOk ? fillRatio.clamp(0.0, 1.0) : 0.0;
    final themeColor   = isSensorOk ? color : Colors.redAccent;
    // Hauteur (en fraction de la cuve) à laquelle se trouve physiquement
    // le capteur de niveau bas — purement indicatif, à ajuster si besoin
    // pour coller à la position réelle du capteur sur la cuve.
    const sensorHeightRatio = 0.15;
    final lineColor = isSensorOk ? Colors.white : Colors.redAccent;

    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      if (onRefill != null)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onRefill,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.45))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_gas_station_outlined,
                    color: Colors.greenAccent, size: 13),
                const SizedBox(width: 4),
                Text('Faire le plein',
                    style: TextStyle(
                        color: Colors.greenAccent[100],
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final w = (constraints.maxWidth * 0.7).clamp(44.0, 76.0);
        const tankHeight = 132.0;

        final tank = Container(
          height: tankHeight,
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
              // Ligne de seuil — matérialise la hauteur physique du capteur
              // de niveau bas (tout ou rien). Le badge OK/Bas à côté de la
              // cuve est relié à cette ligne précise par un petit connecteur.
              Positioned(
                bottom: tankHeight * sensorHeightRatio,
                left: 0,
                right: 0,
                child: Row(children: List.generate(6, (i) {
                  return Expanded(
                    child: Container(
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      color: lineColor.withOpacity(isSensorOk ? 0.4 : 0.9),
                    ),
                  );
                })),
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

        // Badge OK/Bas accolé au trait de seuil via un petit connecteur,
        // pour bien montrer que le badge décrit CETTE ligne précise.
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
              color: (isSensorOk ? Colors.green : Colors.redAccent).withOpacity(0.14),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: (isSensorOk ? Colors.green : Colors.redAccent)
                      .withOpacity(0.5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                isSensorOk ? Icons.check_circle : Icons.warning_amber_rounded,
                color: isSensorOk ? Colors.greenAccent : Colors.redAccent,
                size: 11),
            const SizedBox(width: 3),
            Text(isSensorOk ? 'Niveau OK' : 'Niveau bas',
                style: TextStyle(
                    color: isSensorOk ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900)),
          ]),
        );

        final connector = Container(width: 10, height: 1.5, color: lineColor.withOpacity(0.6));

        return SizedBox(
          height: tankHeight,
          child: Stack(clipBehavior: Clip.none, children: [
            tank,
            Positioned(
              bottom: tankHeight * sensorHeightRatio - 10,
              right: badgeOnRight ? -92 : null,
              left: badgeOnRight ? null : -92,
              child: Row(mainAxisSize: MainAxisSize.min, children: badgeOnRight
                  ? [connector, const SizedBox(width: 2), badge]
                  : [badge, const SizedBox(width: 2), connector]),
            ),
          ]),
        );
      }),
    ]);
  }
}

/// Jauge pompe — même style visuel que TankLevelGauge (cuves), pour que
/// le schéma "réservoirs + pompe" soit cohérent d'un seul coup d'œil.
class PumpLoadGauge extends StatelessWidget {
  final String label;
  final double percent; // 0–100
  final Color color;

  const PumpLoadGauge({
    super.key,
    required this.label,
    required this.percent,
    required this.color,
  });

  // Dégradé vert (0%) -> jaune/orange (50%) -> rouge (100%), pour visualiser
  // la charge moteur d'un coup d'œil.
  static Color _gaugeColor(double percent) {
    final p = percent.clamp(0.0, 100.0);
    const green = Color(0xFF22C55E);
    const yellow = Color(0xFFFACC15);
    const red = Color(0xFFEF4444);
    if (p <= 50) {
      return Color.lerp(green, yellow, p / 50)!;
    }
    return Color.lerp(yellow, red, (p - 50) / 50)!;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (percent / 100).clamp(0.0, 1.0);
    final gaugeColor = _gaugeColor(percent);

    return Column(children: [
      if (label.isNotEmpty) ...[
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
      ],
      LayoutBuilder(builder: (context, constraints) {
        final w = (constraints.maxWidth * 0.55).clamp(34.0, 56.0);
        const gaugeHeight = 92.0;
        return Container(
          height: gaugeHeight,
          width: w,
          decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: [
                BoxShadow(
                    color: gaugeColor.withOpacity(0.15),
                    blurRadius: 10,
                    spreadRadius: 1)
              ]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(alignment: Alignment.bottomCenter, children: [
              FractionallySizedBox(
                heightFactor: ratio,
                widthFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [gaugeColor.withOpacity(0.6), gaugeColor])),
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(height: 2, color: Colors.white54)),
                ),
              ),
              Positioned(
                left: 3, top: 3, bottom: 3,
                width: 9,
                child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10))),
              ),
              // Graduations à 25/50/75%, colorées selon l'échelle vert->rouge
              // à cet endroit précis — ancre visuellement "% par rapport au max".
              for (final mark in [25.0, 50.0, 75.0])
                Positioned(
                  bottom: gaugeHeight * mark / 100,
                  right: 3,
                  child: Container(
                      width: 7,
                      height: 1.5,
                      color: _gaugeColor(mark).withOpacity(0.85)),
                ),
              Center(
                child: Text('${percent.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
              ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 6),
      Text('CHARGE',
          style: TextStyle(
              color: Colors.grey[500],
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3)),
    ]);
  }
}