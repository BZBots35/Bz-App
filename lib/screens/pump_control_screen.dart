// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'pump_debug_screen.dart';
import '../services/lang_service.dart';
import '../services/pump_service.dart';

class PumpControlScreen extends StatefulWidget {
  final models.Document canalisationDoc;
  final models.Document chantierDoc;
  final double epaisseur;
  final String resinType, userName, piBase;
  final int passNum, passesDone, passes;
  // NB: qteParPasse n'est plus utilisé en interne depuis l'ajout du
  // panneau specs modifiables — l'écran recalcule sa propre valeur via
  // un getter (_qteParPasse) dérivé de longueur/diametre/epaisseur,
  // pour rester à jour si ces valeurs sont modifiées en direct. Garde
  // ce paramètre pour compatibilité avec les appels existants.
  final double longueur, diametre, qteParPasse;
  // Quand true, affiche un panneau modifiable (diamètre/longueur/
  // épaisseur) en haut de l'écran — utilisé pour l'accès direct à la
  // pompe sans chantier créé au préalable. Les valeurs passées en
  // paramètre (longueur/diametre/epaisseur) servent alors juste de
  // valeurs de départ, modifiables ensuite depuis ce panneau.
  final bool editableSpecs;

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
    this.editableSpecs = false,
  });

  @override
  State<PumpControlScreen> createState() => _PumpControlScreenState();
}

class _PumpControlScreenState extends State<PumpControlScreen>
    with SingleTickerProviderStateMixin {

  final _lang = LangService();
  final _pumpService = PumpService();

  // Débit max réglable (slider + champ texte + calcul PWM) — une seule
  // source de vérité, à changer ici si jamais la plage doit évoluer.
  static const double _debitMax = 0.8; // L/min

  // Vitesse tracteur max réglable — même principe.
  static const double _vitesseMax = 3; // m/min

  // Débit de référence utilisé pour calculer le débit/vitesse conseillés
  // à partir des specs (mode direct/editableSpecs uniquement). Le débit
  // est figé à cette valeur, et c'est la vitesse tracteur qui est
  // déduite — voir _recalculerDebitVitesseConseilles().
  static const double _debitBaseConseille = 0.25; // L/min

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

  // ── Vidéo timelapse (Pi caméra dédiée, même IP que la pompe, port 5002) ──

  // Base URL de la Pi caméra, déduite de widget.piBase (même hôte, port
  // dédié différent de celui du serveur pompe).
  String get _piCameraBase {
    final uri = Uri.parse(widget.piBase);
    return uri.replace(port: 5002).toString();
  }

  // Démarre l'enregistrement timelapse. Best-effort : une vidéo manquée
  // ne doit jamais bloquer le fonctionnement de la pompe, donc on avale
  // l'erreur ici (juste loguée) plutôt que de la remonter à l'appelant.
  Future<void> _startVideoRecording() async {
    try {
      final resp = await http
          .post(Uri.parse('$_piCameraBase/video/start'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        print("Enregistrement vidéo démarré");
      } else {
        print("Erreur démarrage vidéo (${resp.statusCode}) : ${resp.body}");
      }
    } catch (e) {
      print("Erreur de connexion caméra (démarrage) : $e");
    }
  }

  // Arrête l'enregistrement sans le partager (passe abandonnée sans
  // validation) — libère quand même la caméra côté Pi pour ne pas la
  // laisser bloquée en enregistrement indéfiniment.
  Future<void> _stopVideoRecording() async {
    try {
      await http
          .post(Uri.parse('$_piCameraBase/video/stop'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      print("Erreur arrêt caméra : $e");
    }
  }

  // Arrête l'enregistrement, récupère le fichier fini depuis la Pi
  // caméra, et ouvre la feuille de partage du téléphone — même flux
  // que sharePdf() dans pump_pdf_service.dart, mais pour la vidéo.
  // Tente aussi un upload vers Appwrite Storage (voir _service.uploadVideo)
  // pour que la vidéo reste rattachée au chantier, pas seulement sur le
  // téléphone qui a fait l'inspection. Best-effort : un échec d'upload
  // ne bloque jamais le partage local, qui reste la voie principale.
  Future<void> _finalizeAndShareVideo() async {
    try {
      await http
          .post(Uri.parse('$_piCameraBase/video/stop'))
          .timeout(const Duration(seconds: 5));

      final resp = await http
          .get(Uri.parse('$_piCameraBase/video/latest'))
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        print("Vidéo indisponible (${resp.statusCode})");
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filename =
          'timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(resp.bodyBytes);

      // Sauvegarde directe dans la galerie du téléphone (album dédié),
      // best-effort : un échec ne doit jamais bloquer le partage
      // ci-dessous, qui reste la voie principale.
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putVideo(file.path, album: 'BZBots Pompe');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_lang.t('pumpVideoSavedToGalleryMsg')),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating));
        }
      } catch (e) {
        print("Erreur sauvegarde galerie : $e");
      }

      // Upload Appwrite en tâche de fond — ne bloque pas le partage
      // ci-dessous, et son échec éventuel est silencieux (voir
      // PumpService.uploadVideo).
      unawaited(_pumpService.uploadVideo(resp.bodyBytes, filename).then((fileId) {
        if (fileId != null) {
          _pumpService.appendVideoToCanalisation(widget.canalisationDoc.$id, fileId);
        }
      }));
    } catch (e) {
      print("Erreur récupération/partage vidéo : $e");
    }
  }

  // ── Inspection caméra : enregistrement timelapse manuel, indépendant ──
  // du cycle de passe. Réutilise les mêmes endpoints /video/start et
  // /video/stop que l'enregistrement automatique lié à la passe
  // (_videoRecording), mais déclenché/arrêté à la main par l'opérateur
  // via le bouton dans l'AppBar. Un seul enregistrement à la fois côté
  // Pi caméra (le serveur renvoie 409 sinon) : on évite donc de
  // chevaucher les deux modes.
  bool _inspectionRecording = false;

  Future<void> _toggleInspectionRecording() async {
    if (!_inspectionRecording) {
      if (_videoRecording) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_lang.t('pumpCameraAlreadyRecordingMsg')),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() => _inspectionRecording = true);
      await _startVideoRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_lang.t('pumpCameraInspectionStartedMsg')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
      }
    } else {
      setState(() => _inspectionRecording = false);
      await _finalizeAndShareVideo();
    }
  }

  // Convertit le débit commandé (0 – _debitMax L/min) en pourcentage PWM
  // (0 – 100)
  // À ajuster si la correspondance réelle débit/PWM du moteur diffère.
  int _debitToPwmPercent() {
    return ((_debitCommand / _debitMax) * 100).round().clamp(0, 100);
  }

  // Convertit la vitesse tracteur commandée (0 – _vitesseMax m/min) en
  // pourcentage PWM (0 – 100) pour SPEED4. À ajuster si la correspondance
  // réelle vitesse/PWM du moteur diffère.
  int _vitesseToPwmPercent() {
    return ((_vitesseCommand / _vitesseMax) * 100).round().clamp(0, 100);
  }

  Future<void> _checkPiConnection() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.piBase}/health'),
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

          // État réel du tracteur (moteur 4) — synchronise le bouton avec
          // l'Arduino (ex : coupé automatiquement par un STOP pompe/niveau
          // bas, ou état après reconnexion à l'app).
          final tracteurOnRaw = (data['tracteur_on'] as num?)?.toInt();
          if (tracteurOnRaw != null) _tracteurOn = tracteurOnRaw == 1;

          // Sens réel du tracteur, même logique de synchronisation.
          final tracteurSensRaw = (data['tracteur_sens'] as num?)?.toInt();
          if (tracteurSensRaw != null) _tracteurSensAvant = tracteurSensRaw == 1;
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
  double _debitCommand   = 0.0;   // 0.0 – _debitMax L/min
  double _vitesseCommand = 0.0;   // 0.0 – _vitesseMax m/min

  // Vrai juste après que _recalculerDebitVitesseConseilles() a rempli le
  // champ correspondant — affiche un petit avertissement sous le champ.
  // Repasse à false dès que le client modifie la valeur lui-même (saisie
  // ou slider), qu'il vienne ou non de la suggestion.
  bool _debitEstConseille = false;
  bool _vitesseEstConseillee = false;

  // ── Tracteur (moteur 4) — start/stop indépendant de la pompe ──
  bool _tracteurOn = false;
  bool _tracteurSensAvant = true; // true = avant, false = arrière
  // Le client n'a pas forcément de tracteur physique sur ce chantier
  // (ex: pose manuelle). Quand false, tout ce qui concerne le tracteur
  // (bouton marche/arrêt, sens, réglage vitesse m/min) est désactivé et
  // non interactif — rien n'est envoyé à la Pi pour le moteur 4.
  bool _hasTracteur = true;

  // ── Vidéo timelapse (Pi caméra, port dédié 5002) ──
  // true dès que /video/start a été envoyé pour la passe en cours ;
  // reste true à travers les pauses/reprises de pompe, remis à false
  // uniquement quand la passe se termine réellement (auto ou sortie
  // manuelle) et que la vidéo a été finalisée + partagée.
  bool _videoRecording = false;

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
  // Sans tracteur physique sur le chantier (_hasTracteur == false),
  // aucune télémétrie vitesse4 réelle n'arrive (le moteur 4 ne tourne
  // pas) : l'avancement/la courbe épaisseur ne sont alors pas
  // échantillonnés pour cette passe.
  double get _vitesseForCalc => _hasTracteur ? _vitesse4Reel : 0.0;

  // ── Courbe épaisseur appliquée en fonction du métrage ──
  // Un point ajouté à chaque tick où la pompe avance réellement (vitesse
  // mesurée > 0). Épaisseur (mm) = (débit réel / vitesse réelle) x 1000
  // / (π x diamètre) — inverse de la formule de conso prévisionnelle
  // déjà utilisée ailleurs dans l'app.
  final List<FlSpot> _thicknessSamples = [];

  final _random = math.Random();
  Timer? _timer;
  Timer? _telemetryTimer;
  // Debounce d'envoi pour les sliders débit/vitesse — indépendant de
  // onChangeEnd (peu fiable sur cet écran à cause des reconstructions
  // fréquentes du widget tree via la télémétrie toutes les secondes).
  // Se déclenche ~400ms après le dernier mouvement du slider, que le
  // relâchement ait été détecté proprement ou non.
  Timer? _debitSendDebounce;
  Timer? _vitesseSendDebounce;
  late AnimationController _heroAnimController;

  final TextEditingController _debitFieldCtrl = TextEditingController();
  final TextEditingController _vitesseFieldCtrl = TextEditingController();
  final FocusNode _debitFocus = FocusNode();
  final FocusNode _vitesseFocus = FocusNode();

  // ── Specs modifiables (mode editableSpecs) ────────────
  // Initialisées depuis les valeurs passées par le widget, mais
  // modifiables ensuite via le panneau du haut quand
  // widget.editableSpecs == true. Tout le reste de l'écran lit ces
  // champs plutôt que widget.diametre/longueur/epaisseur directement,
  // pour que le panneau ait un effet immédiat sur les calculs.
  late double _diametre;
  late double _longueur;
  late double _epaisseur;
  late TextEditingController _diametreCtrl;
  late TextEditingController _longueurCtrl;
  late TextEditingController _epaisseurCtrl;

  double get _qteParPasse =>
      _longueur * (math.pi * _diametre * _epaisseur / 1000);

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _diametre  = widget.diametre;
    _longueur  = widget.longueur;
    _epaisseur = widget.epaisseur;
    _diametreCtrl  = TextEditingController(text: _diametre.toStringAsFixed(0));
    _longueurCtrl  = TextEditingController(text: _longueur.toStringAsFixed(1));
    _epaisseurCtrl = TextEditingController(text: _epaisseur.toStringAsFixed(2));
    _metersLeft = _longueur;
    _resinConso = widget.passesDone * _qteParPasse;
    // Initialise le niveau des cuves en tenant compte de ce qui a déjà été
    // consommé sur ce chantier avant l'ouverture de l'écran (cohérent avec
    // l'ancien calcul), le suivi indépendant ne divergera qu'après un
    // premier "Plein" manuel.
    final priorVolume = widget.passesDone * _qteParPasse;
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
    _debitSendDebounce?.cancel();
    _vitesseSendDebounce?.cancel();
    _debitFieldCtrl.dispose();
    _vitesseFieldCtrl.dispose();
    _debitFocus.dispose();
    _vitesseFocus.dispose();
    _diametreCtrl.dispose();
    _longueurCtrl.dispose();
    _epaisseurCtrl.dispose();
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
    final clamped = parsed.clamp(0.0, _debitMax);
    setState(() {
      _debitCommand = clamped;
      _debitEstConseille = false;
    });
    _debitFieldCtrl.text = clamped.toStringAsFixed(2);
    if (_isPumpOn) {
      _sendCmd('SPEED12=${_debitToPwmPercent()}');
      _sendCmd('DEBIT_CIBLE=${clamped.toStringAsFixed(2)}');
    }
  }

  // Applique une valeur de vitesse saisie manuellement (clavier)
  void _applyVitesseInput(String text) {
    if (!_hasTracteur) return;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) {
      _vitesseFieldCtrl.text = _vitesseCommand.toStringAsFixed(2);
      return;
    }
    final clamped = parsed.clamp(0.0, _vitesseMax);
    setState(() {
      _vitesseCommand = clamped;
      _vitesseEstConseillee = false;
    });
    _vitesseFieldCtrl.text = clamped.toStringAsFixed(2);
    if (_tracteurOn) {
      _sendCmd('SPEED4=${_vitesseToPwmPercent()}');
    }
  }

  // Calcule un débit et une vitesse tracteur conseillés à partir des
  // specs actuelles (diamètre/longueur/épaisseur), et les applique
  // directement dans les champs réglables. Utile seulement en mode
  // direct (editableSpecs) — déclenché par le bouton dédié dans
  // _buildEditableSpecsPanel (pas automatique, l'utilisateur valide).
  //
  // Principe géométrique (même formule que _qteParPasse) : pour garder
  // une épaisseur constante le long de la passe,
  //   débit (L/min) = vitesse (m/min) × π × diamètre(mm) × épaisseur(mm) / 1000
  // Le débit est figé à _debitBaseConseille, et on en déduit la vitesse
  // tracteur nécessaire ; si cette vitesse dépasse la capacité du
  // tracteur (_vitesseMax), on la plafonne et on réduit le débit en
  // conséquence pour garder l'épaisseur cible correcte plutôt que de
  // dépasser le matériel.
  void _recalculerDebitVitesseConseilles() {
    final ringFactor = math.pi * _diametre * _epaisseur / 1000; // L par mètre
    if (ringFactor <= 0) return;

    double debit = _debitBaseConseille;
    double vitesse = debit / ringFactor;

    vitesse = vitesse.clamp(0.0, _vitesseMax);
    // Recalcule le débit si la vitesse a dû être replafonnée par
    // _vitesseMax (cas limite : diamètre/épaisseur très grands).
    debit = (vitesse * ringFactor).clamp(0.0, _debitMax);

    _applyDebitInput(debit.toStringAsFixed(2));
    _applyVitesseInput(vitesse.toStringAsFixed(2)); // no-op si !_hasTracteur
    setState(() {
      _debitEstConseille = true;
      _vitesseEstConseillee = _hasTracteur;
    });
  }

  // Recalcule uniquement la vitesse tracteur, à partir du débit
  // actuellement réglé par l'opérateur (qui peut différer de
  // _debitBaseConseille) — contrairement à
  // _recalculerDebitVitesseConseilles() qui figeait le débit, ce calcul
  // part du débit choisi par l'utilisateur et en déduit la vitesse
  // nécessaire pour garder l'épaisseur cible. Bouton dédié à côté du
  // cadran de vitesse.
  void _recalculerVitesseDepuisDebit() {
    if (!_hasTracteur) return;
    final ringFactor = math.pi * _diametre * _epaisseur / 1000; // L par mètre
    if (ringFactor <= 0) return;

    final vitesse = (_debitCommand / ringFactor).clamp(0.0, _vitesseMax);
    _applyVitesseInput(vitesse.toStringAsFixed(2));
    setState(() => _vitesseEstConseillee = true);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        // Note : toutes les valeurs de télémétrie (charges, débit, températures,
        // niveaux) viennent désormais de _fetchTelemetry() en temps réel.

        // ── Conso résine + niveau des cuves — basé sur le débit RÉEL ──
        // Indépendant du mouvement du tracteur : si la pompe distribue de
        // la résine (débit mesuré > 0), les cuves descendent à ce rythme,
        // même si le tracteur n'avance pas (ex: pompe démarrée seule,
        // tracteur pas encore lancé ou temporairement arrêté).
        if (_isPumpOn && _debitReel > 0) {
          _resinConso += _debitReel / 60;
          _resinAppliedThisPass += _debitReel / 60;

          final volumeDeltaMixed = _debitReel / 60; // L consommés cette seconde
          _resineTankRatio = (_resineTankRatio -
                  (volumeDeltaMixed * _ratioResine) / _resineCapaciteL)
              .clamp(0.0, 1.0);
          _durcisseurTankRatio = (_durcisseurTankRatio -
                  (volumeDeltaMixed * _ratioDurcisseur) / _durcisseurCapaciteL)
              .clamp(0.0, 1.0);
        }

        // ── Avancement tracteur — basé sur la vitesse RÉELLE mesurée ──
        // (pas la consigne : si la pompe n'avance pas vraiment à la
        // vitesse demandée, la barre de progression doit le refléter)
        if (_isPumpOn && _vitesseForCalc > 0) {
          final delta = _vitesseForCalc / 60; // 1 seconde → m
          _metersDone += delta;
          _metersLeft  = (_longueur - _metersDone).clamp(0, _longueur);
          _timeElapsed += 1 / 60;

          // ── Échantillon pour la courbe épaisseur/métrage ──
          // Basé sur les mesures RÉELLES (débit et vitesse mesurés), pas
          // sur la consigne — on ignore si la vitesse mesurée est ~nulle
          // pour éviter une division par zéro / valeur aberrante.
          if (_vitesseForCalc > 0.01) {
            final epaisseurInstant = double.parse(
                ((_debitReel / _vitesseForCalc) * 1000 / (math.pi * _diametre))
                    .toStringAsFixed(2));
            _thicknessSamples.add(FlSpot(_metersDone, epaisseurInstant));
          }

          // Passe terminée automatiquement
          if (_metersLeft <= 0.001) {
            _isPumpOn = false;
            _sendCmd('SPEED12=0');
            _sendCmd('DEBIT_CIBLE=0');
            if (_videoRecording) {
              _videoRecording = false;
              _finalizeAndShareVideo();
            }
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
        ? _lang.t('pumpPiUnreachableMsg')
        : _lang.t('pumpArduinoDisconnectedMsg');
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
        ? _lang.t('pumpLevelLowResinDurcisseurMsg')
        : resineLow
            ? _lang.t('pumpLevelLowResinMsg')
            : _lang.t('pumpLevelLowDurcisseurMsg');
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
    // 2. On envoie la vitesse et la consigne de débit juste après
    //    (si le serveur gère le délai)
    Future.delayed(const Duration(milliseconds: 100), () {
       _sendCmd('SPEED12=${_debitToPwmPercent()}');
       _sendCmd('DEBIT_CIBLE=${_debitCommand.toStringAsFixed(2)}');
    });
    // 3. Vidéo timelapse : démarrée une seule fois pour toute la passe.
    //    Si l'opérateur coupe/remet la pompe plusieurs fois pendant la
    //    même passe, l'enregistrement continue déjà, on ne relance pas.
    if (!_videoRecording && !_inspectionRecording) {
      _videoRecording = true;
      _startVideoRecording();
    }
  } else {
    // 1. On envoie l'ordre d'arrêt (STOP)
    _sendCmd('STOP');
  }
}

  // Démarre/arrête le tracteur (moteur 4), indépendamment du cycle de
  // pompage. Même garde-fou de connexion que la pompe (même liaison
  // Arduino) ; pas de contrôle de niveau résine/durcisseur, non
  // pertinent pour le tracteur.
  void _toggleTracteur() {
    if (!_hasTracteur) return;
    if (!_tracteurOn && (!_piConnected || !_arduinoConnected)) {
      final message = !_piConnected
          ? _lang.t('pumpPiUnreachableMsg')
          : _lang.t('pumpArduinoDisconnectedMsg');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent.withOpacity(0.9)),
      );
      return;
    }

    setState(() => _tracteurOn = !_tracteurOn);
    _sendCmd(_tracteurOn ? 'TRACT_ON' : 'TRACT_OFF');
    if (_tracteurOn) {
      // Applique la vitesse actuellement réglée sur le slider, sinon le
      // tracteur repartirait à la vitesse par défaut de l'Arduino.
      Future.delayed(const Duration(milliseconds: 100), () {
        _sendCmd('SPEED4=${_vitesseToPwmPercent()}');
      });
    }
  }

  // Change le sens de rotation du tracteur. Volontairement bloqué tant
  // que le tracteur tourne (_tracteurOn) : inverser le sens sous charge
  // pourrait forcer brutalement sur la mécanique. Il faut d'abord
  // l'arrêter.
  void _setTracteurSens(bool avant) {
    if (!_hasTracteur || _tracteurOn || avant == _tracteurSensAvant) return;
    setState(() => _tracteurSensAvant = avant);
    _sendCmd(avant ? 'TRACT_SENS_AVANT' : 'TRACT_SENS_ARRIERE');
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

    final target = math.max(30, (_longueur / 0.1).ceil());
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
    final targetEpaisseur = _epaisseur;
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
                Text(_lang.t('pumpChartTitle'),
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
                              labelResolver: (line) =>
                                  '${_lang.t('pumpChartTargetPrefix')}${targetEpaisseur.toStringAsFixed(1)}mm'),
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
                  child: Text(_lang.t('pumpChartNotEnoughData'),
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
      _sendCmd('DEBIT_CIBLE=0');
      if (_videoRecording) {
        _videoRecording = false;
        _stopVideoRecording();
      }
      if (_inspectionRecording) {
        _inspectionRecording = false;
        _stopVideoRecording();
      }
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
              ? _lang.t('pumpLowLevelBothMsg')
              : resineLow
                  ? _lang.t('pumpLowLevelResinMsg')
                  : _lang.t('pumpLowLevelDurcisseurMsg');

          return AlertDialog(
            backgroundColor: const Color(0xFF0D0D0D),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1)),
            title: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              const SizedBox(width: 8),
              Text(_lang.t('pumpLevelLowLabel'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(message,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
              const SizedBox(height: 4),
              Text(_lang.t('pumpLowLevelFillNowMsg'),
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
              const SizedBox(height: 18),
              Text('$secondsLeft s',
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 36, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(_lang.t('pumpLowLevelCountdownSuffix'),
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
                child: Text(_lang.t('pumpStopNowBtn'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
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
          Text('${_lang.t('pumpRefillTitlePrefix')}$label',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
        content: Text(
          '${_lang.t('pumpRefillConfirmPrefix')}$label${_lang.t('pumpRefillConfirmSuffix')}',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_lang.t('cancel'), style: TextStyle(color: Colors.grey[400]))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text(_lang.t('confirm'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
    if (confirm == true) onConfirm();
  }

  // ── Panneau specs modifiables (accès direct sans chantier) ──
  // Permet de saisir/ajuster diamètre, longueur et épaisseur cible
  // directement sur cet écran, sans être passé par un chantier créé au
  // préalable. Toute modification met à jour _diametre/_longueur/
  // _epaisseur, dont dépendent déjà tous les calculs de l'écran
  // (progression, badge DN, courbe épaisseur, qté/passe...).
  Widget _buildEditableSpecsPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt, color: Colors.amber, size: 16),
          const SizedBox(width: 6),
          Text(_lang.t('pumpControlSpecsTitle'),
            style: TextStyle(color: Colors.grey[400], fontSize: 9,
              fontWeight: FontWeight.w900, letterSpacing: 1.3)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _specField(_diametreCtrl, _lang.t('pumpControlDiametreLabel'),
            (v) => setState(() => _diametre = double.tryParse(v) ?? _diametre))),
          const SizedBox(width: 8),
          Expanded(child: _specField(_longueurCtrl, _lang.t('pumpControlLongueurLabel'),
            (v) => setState(() => _longueur = double.tryParse(v) ?? _longueur))),
          const SizedBox(width: 8),
          Expanded(child: _specField(_epaisseurCtrl, _lang.t('pumpControlEpaisseurLabel'),
            (v) => setState(() => _epaisseur = double.tryParse(v) ?? _epaisseur))),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _recalculerDebitVitesseConseilles,
            icon: const Icon(Icons.calculate_outlined, size: 16, color: Colors.amber),
            label: Text(_lang.t('pumpControlSuggestDebitVitesseBtn'),
              style: TextStyle(color: Colors.amber[200], fontSize: 11,
                fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(color: Colors.amber.withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(_lang.t('pumpControlQtePasseEstimeeLabel'),
            style: TextStyle(color: Colors.grey[500], fontSize: 10)),
          Text('${_qteParPasse.toStringAsFixed(2)} L',
            style: const TextStyle(color: Color(0xFF22D3EE),
              fontWeight: FontWeight.w900, fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _specField(TextEditingController ctrl, String label,
      void Function(String) onChanged) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 10),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.amber, width: 1.5))),
    );
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
            _headerBadge('DN${_diametre.toInt()}',
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
            icon: Icon(
              _inspectionRecording ? Icons.videocam : Icons.camera_alt_outlined,
              color: _inspectionRecording ? Colors.redAccent : Colors.white70,
              size: 20),
            tooltip: _inspectionRecording
              ? _lang.t('pumpCameraStopInspectionTooltip')
              : _lang.t('pumpCameraInspectionTooltip'),
            onPressed: _toggleInspectionRecording,
          ),
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
          // ── Specs modifiables (accès direct sans chantier) ──
          if (widget.editableSpecs) _buildEditableSpecsPanel(),
          if (widget.editableSpecs) const SizedBox(height: 14),
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
    final progress = _longueur > 0
        ? (_metersDone / _longueur).clamp(0.0, 1.0)
        : 0.0;
    final remainingMins =
        _vitesseForCalc > 0 ? _metersLeft / _vitesseForCalc : 0.0;

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
              Text(_isPumpOn ? _lang.t('statusInProgress') : _lang.t('pumpStatusStoppedLabel'),
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
                        '${_metersDone.toStringAsFixed(1).replaceAll('.', ',')} / ${_longueur.toStringAsFixed(1).replaceAll('.', ',')} m',
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
                  ? '${_lang.t('pumpElapsedRunningPrefix')}${_fmt(remainingMins)}'
                  : '${_lang.t('pumpElapsedStoppedPrefix')}${_fmt(remainingMins)}${_lang.t('pumpElapsedStoppedSuffix')}',
              style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),

          // ── Détails secondaires, en mini-cartes à icônes ──
          Row(children: [
            Expanded(
                child: _statCard(Icons.timer_outlined, _lang.t('pumpControlTimeElapsedLabel'),
                    _fmt(_timeElapsed), Colors.white)),
            const SizedBox(width: 8),
            Expanded(
                child: _statCard(Icons.water_drop_outlined, _lang.t('pumpControlResinConsumedLabel'),
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
        const SizedBox(height: 12),

        // ── Le client a-t-il un tracteur sur ce chantier ? ──
        // Si non, tout ce qui concerne le tracteur (bouton marche/
        // arrêt, sens, réglage vitesse m/min) est désactivé plus bas.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08))),
          child: Row(children: [
            Icon(Icons.cable,
                color: _hasTracteur ? const Color(0xFFD4A574) : Colors.grey[600],
                size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_lang.t('pumpControlTracteurAvailableLabel'),
                style: TextStyle(color: Colors.grey[300], fontSize: 11,
                    fontWeight: FontWeight.w700))),
            Switch(
              value: _hasTracteur,
              activeColor: const Color(0xFFD4A574),
              onChanged: (v) => setState(() {
                _hasTracteur = v;
                // Si on désactive le tracteur alors qu'il tournait
                // encore, on l'arrête proprement côté Pi.
                if (!v && _tracteurOn) {
                  _tracteurOn = false;
                  _sendCmd('TRACT_OFF');
                }
              }),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Bouton On/Off moteur ────────────────
        Builder(builder: (context) {
          final notConnected = !_piConnected || !_arduinoConnected;
          final levelLow = !_niveauResineOk || !_niveauDurcisseurOk;
          final startBlocked = !_isPumpOn && (notConnected || levelLow);
          final blockedLabel = !_isPumpOn && notConnected
              ? (!_piConnected
                  ? _lang.t('pumpPiUnreachableShort')
                  : _lang.t('pumpArduinoDisconnectedShort'))
              : _lang.t('pumpLevelLowRefillBtnLabel');
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
                        : (_isPumpOn
                            ? _lang.t('pumpStopPumpBtn')
                            : _lang.t('pumpStartPumpBtn')),
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

        const SizedBox(height: 10),

        // ── Bloc tracteur : bouton marche/arrêt + sens ──
        // Grisé, non interactif et cadenassé si le client n'a pas de
        // tracteur sur ce chantier (voir le switch "Tracteur disponible"
        // plus haut).
        _lockableSection(
          locked: !_hasTracteur,
          child: Column(children: [
              // ── Bouton On/Off tracteur (moteur 4, indépendant de la pompe) ──
              Builder(builder: (context) {
                final notConnected = !_piConnected || !_arduinoConnected;
                final startBlocked = !_tracteurOn && notConnected;
                final blockedLabel = !_piConnected
                    ? _lang.t('pumpPiUnreachableShort')
                    : _lang.t('pumpArduinoDisconnectedShort');
                return GestureDetector(
                  onTap: _toggleTracteur,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: startBlocked
                          ? Colors.white.withOpacity(0.03)
                          : (_tracteurOn
                              ? Colors.red.withOpacity(0.15)
                              : Colors.green.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: startBlocked
                              ? Colors.white.withOpacity(0.1)
                              : (_tracteurOn
                                  ? Colors.red.withOpacity(0.6)
                                  : Colors.green.withOpacity(0.5)),
                          width: 1.5),
                      boxShadow: startBlocked
                          ? []
                          : [
                              BoxShadow(
                                  color: (_tracteurOn ? Colors.red : Colors.green)
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
                            : (_tracteurOn ? Icons.stop_circle : Icons.play_circle),
                        color: startBlocked
                            ? Colors.grey[600]
                            : (_tracteurOn ? Colors.redAccent : Colors.greenAccent),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          startBlocked
                              ? blockedLabel
                              : (_tracteurOn
                                  ? _lang.t('pumpStopTracteurBtn')
                                  : _lang.t('pumpStartTracteurBtn')),
                          style: TextStyle(
                            color: startBlocked
                                ? Colors.grey[500]
                                : (_tracteurOn ? Colors.redAccent : Colors.greenAccent),
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

              const SizedBox(height: 10),

              // ── Sélecteur de sens tracteur (avant/arrière) ──
              // Désactivé tant que le tracteur tourne (voir _setTracteurSens).
              Row(children: [
                Expanded(
                  child: _tracteurSensButton(
                    label: _lang.t('pumpDirForwardLabel'),
                    icon: Icons.arrow_upward,
                    selected: _tracteurSensAvant,
                    onTap: () => _setTracteurSens(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tracteurSensButton(
                    label: _lang.t('pumpDirBackwardLabel'),
                    icon: Icons.arrow_downward,
                    selected: !_tracteurSensAvant,
                    onTap: () => _setTracteurSens(false),
                  ),
                ),
              ]),
            ]),
        ),
      ]),
    );
  }

  // Enveloppe un bloc de contrôle pour le griser, le rendre non cliquable,
  // et afficher un cadenas centré par-dessus quand `locked` est vrai —
  // pour que ce soit visuellement clair qu'il est désactivé volontairement
  // (ex : pas de tracteur sur ce chantier) et pas juste indisponible
  // temporairement (comme un défaut de connexion Pi/Arduino).
  Widget _lockableSection({required Widget child, required bool locked}) {
    return Stack(alignment: Alignment.center, children: [
      Opacity(
        opacity: locked ? 0.35 : 1.0,
        child: IgnorePointer(ignoring: locked, child: child),
      ),
      if (locked)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(Icons.lock_outline, color: Colors.grey[400], size: 22),
        ),
    ]);
  }

  // Segment de sélection du sens du tracteur (avant/arrière). Grisé et
  // non cliquable tant que le tracteur tourne, pour éviter une inversion
  // sous charge.
  Widget _tracteurSensButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final disabled = _tracteurOn;
    final color = disabled
        ? Colors.grey[700]!
        : (selected ? const Color(0xFFD4A574) : Colors.grey[500]!);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected && !disabled
              ? const Color(0xFFD4A574).withOpacity(0.12)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected && !disabled
                  ? const Color(0xFFD4A574).withOpacity(0.5)
                  : Colors.white.withOpacity(0.08),
              width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
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
            Text(_lang.t('pumpMeasuredLabel'),
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            SpeedometerGauge(
              currentSpeed: _debitReel,
              maxSpeed: _debitMax,
              unit: 'L/min',
              color: const Color(0xFF60A5FA),
              size: 130,
            ),
            const SizedBox(height: 10),
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            const SizedBox(height: 10),
            Text(_lang.t('pumpSettingLabel'),
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
                max: _debitMax,
                divisions: (_debitMax * 100).round(),
                activeColor: const Color(0xFF60A5FA),
                inactiveColor: Colors.grey[800],
                onChanged: (val) => setState(() {
                  _debitCommand = val;
                  _debitEstConseille = false;
                  if (!_debitFocus.hasFocus) {
                    _debitFieldCtrl.text = val.toStringAsFixed(2);
                  }
                  // Debounce : envoie ~400ms après le dernier mouvement,
                  // sans dépendre de onChangeEnd (peu fiable ici).
                  _debitSendDebounce?.cancel();
                  _debitSendDebounce = Timer(const Duration(milliseconds: 400), () {
                    if (_isPumpOn) {
                      _sendCmd('SPEED12=${_debitToPwmPercent()}');
                      _sendCmd('DEBIT_CIBLE=${_debitCommand.toStringAsFixed(2)}');
                    }
                  });
                }),
                onChangeEnd: (val) {
                  // Filet de sécurité si onChangeEnd se déclenche bien —
                  // annule le debounce en attente pour éviter un double envoi.
                  _debitSendDebounce?.cancel();
                  if (_isPumpOn) {
                    _sendCmd('SPEED12=${_debitToPwmPercent()}');
                    _sendCmd('DEBIT_CIBLE=${val.toStringAsFixed(2)}');
                  }
                },
              ),
            ),
            if (_debitEstConseille) ...[
              const SizedBox(height: 4),
              Text(_lang.t('pumpDebitConseilleMsg'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.amber[200], fontSize: 8, height: 1.3)),
            ],
          ])),

          const SizedBox(width: 16),

          // Vitesse
          Expanded(child: _lockableSection(
            locked: !_hasTracteur,
            child: Column(children: [
            Text(_lang.t('pumpMeasuredLabel'),
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            SpeedometerGauge(
                currentSpeed: _vitesse4Reel, maxSpeed: _vitesseMax, size: 130),
            const SizedBox(height: 10),
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            const SizedBox(height: 10),
            Text(_lang.t('pumpSettingLabel'),
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
                enabled: _hasTracteur,
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
                max: _vitesseMax,
                divisions: (_vitesseMax * 100).round(),
                activeColor: const Color(0xFFD4A574),
                inactiveColor: Colors.grey[800],
                onChanged: !_hasTracteur ? null : (val) => setState(() {
                  _vitesseCommand = val;
                  _vitesseEstConseillee = false;
                  if (!_vitesseFocus.hasFocus) {
                    _vitesseFieldCtrl.text = val.toStringAsFixed(2);
                  }
                  // Debounce : envoie ~400ms après le dernier mouvement,
                  // sans dépendre de onChangeEnd (peu fiable ici).
                  _vitesseSendDebounce?.cancel();
                  _vitesseSendDebounce = Timer(const Duration(milliseconds: 400), () {
                    if (_tracteurOn) {
                      _sendCmd('SPEED4=${_vitesseToPwmPercent()}');
                    }
                  });
                }),
                onChangeEnd: !_hasTracteur ? null : (val) {
                  _vitesseSendDebounce?.cancel();
                  if (_tracteurOn) {
                    _sendCmd('SPEED4=${_vitesseToPwmPercent()}');
                  }
                },
              ),
            ),
            if (_vitesseEstConseillee) ...[
              const SizedBox(height: 4),
              Text(_lang.t('pumpVitesseConseilleeMsg'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.amber[200], fontSize: 8, height: 1.3)),
            ],
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _hasTracteur ? _recalculerVitesseDepuisDebit : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                      color: (_hasTracteur ? Colors.amber : Colors.grey)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: (_hasTracteur ? Colors.amber : Colors.grey)
                              .withOpacity(0.4))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calculate_outlined,
                            size: 13,
                            color: _hasTracteur
                                ? Colors.amber[200]
                                : Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('Recalculer',
                            style: TextStyle(
                                color: _hasTracteur
                                    ? Colors.amber[200]
                                    : Colors.grey[600],
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ]),
                ),
              ),
            ),
          ]),
          )),
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
            Text(
              _lang.t('pumpDiagramTitle'),
              style: const TextStyle(
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
                      Text(_lang.t('pumpFeedResinInletLabel'),
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
                      Text(_lang.t('pumpFeedDurcisseurInletLabel'),
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
                          label: '${_lang.t('pumpControlPumpLabel')} 1',
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
                          label: '${_lang.t('pumpControlPumpLabel')} 2', 
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

  final _lang = LangService();

  TankLevelGauge({
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
                Text(_lang.t('pumpRefillBtnLabel'),
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
            Text(isSensorOk ? _lang.t('pumpLevelOkLabel') : _lang.t('pumpLevelLowLabel'),
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

  final _lang = LangService();

  PumpLoadGauge({
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
      Text(_lang.t('pumpLoadLabel'),
          style: TextStyle(
              color: Colors.grey[500],
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3)),
    ]);
  }
}