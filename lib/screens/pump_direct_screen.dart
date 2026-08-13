// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/auth_service.dart';
import '../services/lang_service.dart';
import 'pump_control_screen.dart';

/// Point d'entrée pour l'accès direct à la pompe, SANS chantier ni
/// canalisation créés au préalable. Ouvre directement le vrai
/// PumpControlScreen (editableSpecs: true), qui affiche alors en haut
/// de son propre écran un panneau permettant de saisir/ajuster
/// diamètre, longueur et épaisseur cible — pas d'écran de formulaire
/// séparé avant.
///
/// Les valeurs ci-dessous (diametre/longueur/epaisseur) ne sont que des
/// valeurs de DÉPART pour ce panneau ; le client les modifie ensuite
/// directement sur l'écran de contrôle.
///
/// ⚠️ canalisationDoc/chantierDoc sont des documents Appwrite fictifs,
/// gardés uniquement en mémoire (jamais envoyés au serveur) — juste là
/// pour satisfaire les paramètres requis de PumpControlScreen. Les
/// sauvegardes qu'il tente de faire (courbe de la passe, résine réelle
/// appliquée) échoueront donc silencieusement — déjà un comportement
/// non bloquant prévu par PumpControlScreen lui-même.
///
/// ⚠️ resinType n'est pas demandé au client ici : valeur par défaut
/// 'spraycoat_plus' (même défaut qu'à la création d'un chantier). Idem
/// pour "passes", fixé à 1 (une seule passe pour ce mode direct).
class PumpDirectScreen extends StatefulWidget {
  const PumpDirectScreen({super.key});

  @override
  State<PumpDirectScreen> createState() => _PumpDirectScreenState();
}

class _PumpDirectScreenState extends State<PumpDirectScreen> {
  static const String _piBase = 'http://10.42.0.1:5000';
  static const String _defaultResinType = 'spraycoat_plus';

  final _auth = AuthService();
  final _lang = LangService();
  String _userName = 'Opérateur';
  bool _loading = true;

  late models.Document _fakeChantier;
  late models.Document _fakeCanalisation;

  @override
  void initState() {
    super.initState();
    _userName = _lang.t('pumpDirectDefaultOperatorName');
    _init();
  }

  Future<void> _init() async {
    final user = await _auth.getCurrentUser();
    final now = DateTime.now();

    _fakeChantier = models.Document.fromMap({
      '\$id': 'direct_${now.millisecondsSinceEpoch}',
      '\$collectionId': 'pump_chantiers',
      '\$databaseId': 'direct',
      '\$createdAt': now.toIso8601String(),
      '\$updatedAt': now.toIso8601String(),
      '\$permissions': [],
      'nom': 'Accès direct pompe',
      'rue': '', 'ville': '', 'batiment': '', 'company': '',
      'date': now.toIso8601String().split('T').first,
      'resinType': _defaultResinType,
      'epaisseur': '0.75',
      'desiredPasses': 1,
    });

    _fakeCanalisation = models.Document.fromMap({
      '\$id': 'direct_canal_${now.millisecondsSinceEpoch}',
      '\$collectionId': 'pump_canalisations',
      '\$databaseId': 'direct',
      '\$createdAt': now.toIso8601String(),
      '\$updatedAt': now.toIso8601String(),
      '\$permissions': [],
      'label': 'Direct',
      'longueur': '10',
      'diametre': '100',
      'passes': 1,
      'passesDone': 0,
      'statut': 'en_cours',
    });

    if (mounted) {
      setState(() {
        if (user != null) _userName = user.name;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF050505),
        body: Center(child: CircularProgressIndicator(
          color: Color(0xFF22D3EE))),
      );
    }

    return PumpControlScreen(
      canalisationDoc: _fakeCanalisation,
      chantierDoc:     _fakeChantier,
      epaisseur:       0.75,
      resinType:       _defaultResinType,
      userName:        _userName,
      piBase:          _piBase,
      passNum:         1,
      passesDone:      0,
      passes:          1,
      longueur:        10,
      diametre:        100,
      qteParPasse:     10 * (math.pi * 100 * 0.75 / 1000),
      editableSpecs:   true,
    );
  }
}
