// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/lang_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/app_roles.dart';
import '../services/bzlight_modules_service.dart';
import '../widgets/lang_selector.dart';
import 'cart_screen.dart';
import 'cart_badge.dart';
import 'bz_tutorial.dart';

class BzLightModulesScreen extends StatefulWidget {
  final String bzl;
  final String robotSerial;
  final List<Map<String, String>> modules;
  final String userRole;
  const BzLightModulesScreen({super.key,
    required this.bzl,
    required this.robotSerial,
    required this.modules,
    this.userRole = ''});
  @override
  State<BzLightModulesScreen> createState() => _BzLightModulesScreenState();
}

class _BzLightModulesScreenState extends State<BzLightModulesScreen> {
  final _lang        = LangService();
  final _auth        = AuthService();
  final _cart        = CartService();
  final _modulesService = BzlightModulesService();
  final _tutorialKey = GlobalKey<BzTutorialState>();

  String _reseller = '';
  bool _bulkUpdating = false;
  late List<Map<String, String>> _mods;

  bool get _canEditVersion =>
      AppRoles.hasMinimumRole(widget.userRole, AppRoles.distributeur);

  // Mapping BZ → Picote (pour tous les revendeurs non-Robocana)
  static const _picoteRefs = {
    'BZL-012':   '900004657',
    'BZL-021-A': '900004659',
    'BZL-021-B': '900004660',
  };

  // Mapping bzl → référence Picote du module entier
  static const _picoteBzlRefs = {
    'BZL1': '1270001001',
    'BZL2': '1270001002',
    'BZL3': '1270001003',
    'BZL4': '1270001004',
  };

  bool get _isPicote => _reseller.isNotEmpty &&
      !_reseller.toLowerCase().contains('robocana');

  String _displayId(String id) {
    if (!_isPicote) return id;
    return _picoteRefs[id] ?? id;
  }

  List<TutorialStep> get _tutorialSteps => [
    TutorialStep(title: 'Ajouter au panier', description: 'Appuyez sur ce bouton pour ajouter un module à votre panier de commande.', targetOffset: const Offset(0.5, 0.80), targetSize: 45),
    TutorialStep(title: 'Icône panier', description: 'Le panier en haut à droite affiche le nombre d\'articles. Appuyez pour consulter ou envoyer votre devis.', targetOffset: const Offset(0.82, 0.06), targetSize: 28),
  ];

  @override
  void initState() {
    super.initState();
    _mods = List<Map<String, String>>.from(widget.modules);
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadReseller();
  }

  Future<void> _loadReseller() async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    final reseller = await _auth.getUserReseller(user.$id);
    if (mounted) setState(() => _reseller = reseller);
  }

  Future<void> _applySeriesVersion() async {
    final controller = TextEditingController();

    final newVersion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0F),
        title: Text('Version pour toute la série ${widget.bzl}',
          style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Cette action va écraser la version de ${_mods.length} pièce(s).',
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'ex: v1, v2, v3',
              hintStyle: TextStyle(color: Colors.grey[600]),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFEAB308))),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: Colors.grey[500]))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Appliquer à toute la série',
              style: TextStyle(color: Color(0xFFEAB308), fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (newVersion == null || newVersion.isEmpty) return;

    setState(() => _bulkUpdating = true);

    int success = 0, failed = 0;
    for (final mod in _mods) {
      final docId = mod['docId'] ?? '';
      if (docId.isEmpty) { failed++; continue; }
      try {
        await _modulesService.updateModuleVersion(docId, newVersion);
        success++;
      } catch (e) {
        failed++;
      }
    }

    if (mounted) {
      setState(() {
        _mods = _mods.map((m) =>
          (m['docId'] ?? '').isNotEmpty ? {...m, 'version': newVersion} : m
        ).toList();
        _bulkUpdating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0
          ? '✅ $success pièce(s) mise(s) à jour'
          : '⚠️ $success ok, $failed échec(s)'),
        backgroundColor: failed == 0 ? const Color(0xFFEAB308) : Colors.orange[800]));
    }
  }

  Future<void> _editVersion(Map<String, String> mod) async {
    final docId = mod['docId'] ?? '';
    if (docId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Ce module n\'est pas encore synchronisé sur Appwrite'),
        backgroundColor: Colors.red));
      return;
    }
    final currentVersion = mod['version'] ?? '';
    final controller = TextEditingController(text: currentVersion);

    final newVersion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0F),
        title: const Text('Modifier la version',
          style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ex: v1, v2, v3',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEAB308))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: Colors.grey[500]))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enregistrer',
              style: TextStyle(color: Color(0xFFEAB308), fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (newVersion == null || newVersion == currentVersion) return;

    try {
      await _modulesService.updateModuleVersion(docId, newVersion);
      if (mounted) {
        setState(() {
          final idx = _mods.indexWhere((m) => m['docId'] == docId);
          if (idx != -1) _mods[idx] = {..._mods[idx], 'version': newVersion};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('❌ Échec de la mise à jour'),
          backgroundColor: Colors.red[800]));
      }
    }
  }

  Future<void> _addToCart(Map<String, String> mod) async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    await _cart.addItem(user.$id, CartItem(
      id:          mod['id'] ?? '',
      name:        mod['nameKey'] != null ? _lang.t(mod['nameKey']!) : (mod['id'] ?? ''),
      version:     mod['version'] ?? '',
      robotSerial: widget.robotSerial,
      img:         mod['img'] ?? '',
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.shopping_cart, color: Colors.black, size: 16),
          const SizedBox(width: 8),
          Text('${mod['id']} ${_lang.t('cartAdded')}',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: const Color(0xFFEAB308),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(
          _isPicote && _picoteBzlRefs.containsKey(widget.bzl)
            ? '${_lang.t("components").split(" ").first} ${widget.bzl} — ${_picoteBzlRefs[widget.bzl]}'
            : '${_lang.t("components").split(" ").first} ${widget.bzl}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
            letterSpacing: 2, fontSize: 14)),
        actions: [
          if (_canEditVersion)
            IconButton(
              icon: _bulkUpdating
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEAB308)))
                : const Icon(Icons.layers, color: Color(0xFFEAB308), size: 20),
              tooltip: 'Définir la version pour toute la série',
              onPressed: _bulkUpdating ? null : _applySeriesVersion),
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white54, size: 20),
            onPressed: () => _tutorialKey.currentState?.show()),
          CartBadge(), LangSelector(), const SizedBox(width: 8)],
      ),
      body: BzTutorial(
        key: _tutorialKey,
        tutorialKey: 'bzlight_modules',
        steps: _tutorialSteps,
        child: _mods.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inventory_2_outlined, color: Colors.grey[700], size: 48),
              const SizedBox(height: 12),
              Text(_lang.t('noComponents'), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ]))
          : CustomScrollView(
              slivers: [
                // ── Image éclatée interactive BZL2 ──────────
                if (widget.bzl == 'BZL1' || widget.bzl == 'BZL2' || widget.bzl == 'BZL3')
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.08))),
                      child: Column(children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          child: _BzlExplodedView(
                            bzl: widget.bzl,
                            modules: _mods,
                            onAddToCart: _addToCart,
                            isPicote: _isPicote,
                            picoteRefs: _picoteRefs,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.touch_app, color: Colors.grey[600], size: 14),
                            const SizedBox(width: 6),
                            Text('Appuyez sur une pièce pour commander',
                              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                          ])),
                      ]),
                    ),
                  ),

                // ── Grille modules ───────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final mod = _mods[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0A0F),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.2))),
                          child: Column(children: [
                            Expanded(child: Padding(padding: const EdgeInsets.all(12),
                              child: ClipRRect(borderRadius: BorderRadius.circular(10),
                                child: Image.asset(mod['img'] ?? '', fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(10)),
                                    child: Icon(Icons.memory,
                                      color: const Color(0xFFEAB308).withOpacity(0.4), size: 44)))))),
                            Text(mod['nameKey'] != null ? _lang.t(mod['nameKey']!) : _displayId(mod['id'] ?? ''), style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                            if (_isPicote && _picoteRefs.containsKey(mod['id'])) ...[
                              const SizedBox(height: 2),
                              Text(_picoteRefs[mod['id']]!, style: TextStyle(
                                color: Colors.grey[500], fontSize: 10, fontFamily: 'monospace')),
                            ],
                            const SizedBox(height: 4),
                            if ((mod['version'] ?? '').isNotEmpty || _canEditVersion)
                            GestureDetector(
                              onTap: _canEditVersion ? () => _editVersion(mod) : null,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAB308).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.3))),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('${_lang.t('version')} ${mod['version'] ?? '—'}',
                                    style: const TextStyle(color: Color(0xFFEAB308),
                                      fontSize: 10, fontWeight: FontWeight.w700)),
                                  if (_canEditVersion) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit, size: 10, color: Color(0xFFEAB308)),
                                  ],
                                ]))),
                            GestureDetector(
                              onTap: () => _addToCart(mod),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAB308).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.4))),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.add_shopping_cart, color: Color(0xFFEAB308), size: 14),
                                  const SizedBox(width: 6),
                                  Text(_lang.t('cartAdd'), style: const TextStyle(
                                    color: Color(0xFFEAB308), fontSize: 10, fontWeight: FontWeight.w700)),
                                ]),
                              ),
                            ),
                          ]),
                        );
                      },
                      childCount: _mods.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 14,
                      mainAxisSpacing: 14, childAspectRatio: 0.85),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// VUE ÉCLATÉE INTERACTIVE
// ══════════════════════════════════════════════════
class _BzlExplodedView extends StatefulWidget {
  final String bzl;
  final List<Map<String, String>> modules;
  final Future<void> Function(Map<String, String>) onAddToCart;
  final bool isPicote;
  final Map<String, String> picoteRefs;

  const _BzlExplodedView({
    required this.bzl,
    required this.modules,
    required this.onAddToCart,
    required this.isPicote,
    required this.picoteRefs,
  });

  @override
  State<_BzlExplodedView> createState() => _BzlExplodedViewState();
}

class _BzlExplodedViewState extends State<_BzlExplodedView> {
  final _lang = LangService();
  // Hotspots BZL1 — positions à ajuster par l'utilisateur
  static const _hotspotsBZL1 = [
    {'id': 'BZL-011',               'dx': 0.29, 'dy': 0.64},
    {'id': 'BZL-012',               'dx': 0.69, 'dy': 0.22},
    {'id': 'BZL-013',               'dx': 0.8, 'dy': 0.43},
    {'id': 'BZL-100',               'dx': 0.51, 'dy': 0.76},
    {'id': 'BZL-101',               'dx': 0.215, 'dy': 0.46},
    {'id': 'BZL-102',               'dx': 0.355, 'dy': 0.11},
    {'id': 'BZL-103',               'dx': 0.54, 'dy': 0.27},
    {'id': 'BZL-104',               'dx': 0.6, 'dy': 0.22},
    {'id': 'BZL-105',               'dx': 0.215, 'dy': 0.405},
    {'id': 'BZL-106',               'dx': 0.38, 'dy': 0.64},
    {'id': 'BZL-107',               'dx': 0.38, 'dy': 0.183},
    {'id': 'BZL-117',               'dx': 0.855, 'dy': 0.64},
    {'id': 'FIJ-ORN-3x1',           'dx': 0.23, 'dy': 0.51},
    {'id': 'FIJ-ORN-28x1.5',        'dx': 0.233, 'dy': 0.56},
    {'id': 'FIJ-ORN-65x1',          'dx': 0.12, 'dy': 0.31},
    {'id': 'FIQ-RT-7.62-1.4-57.1',  'dx': 0.84, 'dy': 0.47},
    {'id': 'FIT-RBS-626',           'dx': 0.205, 'dy': 0.345},
    {'id': 'FIV-CTO-M3-10-Z',       'dx': 0.48, 'dy': 0.22},
    {'id': 'FIV-CTO-M4-16-Z',       'dx': 0.83, 'dy': 0.76},
    {'id': 'FIV-CTO-M4-20-Z',       'dx': 0.49, 'dy': 0.64},
    {'id': 'FIV-CTO-M4-20-Z',       'dx': 0.855, 'dy': 0.7},
    {'id': 'FIV-FTO-M3-08-Z',       'dx': 0.315, 'dy': 0.065},
    {'id': 'FIV-HC-M4-20-Z',        'dx': 0.765, 'dy': 0.37},
    {'id': 'FIV-HCB-M6-14',         'dx': 0.61, 'dy': 0.76},
    {'id': 'FIV-ROG-04-I',          'dx': 0.71, 'dy': 0.76},
    {'id': 'FIV-ROG-05',            'dx': 0.84, 'dy': 0.585},
  ];

  static const _hotspotsBZL2 = [
    {'id': 'BZL-021-B',             'dx': 0.22, 'dy': 0.32},
    {'id': 'BZL-021-A',             'dx': 0.895, 'dy': 0.70},
    {'id': 'BZL-201',                'dx': 0.84, 'dy': 0.36},
    {'id': 'BZL-203',                'dx': 0.79, 'dy': 0.46},
    {'id': 'BZL-204',                'dx': 0.31, 'dy': 0.75},
    {'id': 'BZL-202',                'dx': 0.47, 'dy': 0.89},
    {'id': 'FIJ-ORN-28x1.5',        'dx': 0.76, 'dy': 0.09},
    {'id': 'FIJ-ORN-11x1.5',        'dx': 0.908, 'dy': 0.256},
    {'id': 'FIV-FTO-M3-08-Z',       'dx': 0.235, 'dy': 0.665},
    {'id': 'FIV-CTO-M3-10-Z',       'dx': 0.53, 'dy': 0.66},
    {'id': 'FIV-ROG-03-I',          'dx': 0.52, 'dy': 0.555},
    {'id': 'FIV-ROG-03-I',          'dx': 0.4, 'dy': 0.145},
    {'id': 'FIV-ROG-03-I',          'dx': 0.82, 'dy': 0.51},
    {'id': 'FIQ-RC-15.24-1.4-38.1', 'dx': 0.37, 'dy': 0.81},
    {'id': 'FIV-CHC-M3-20',         'dx': 0.38,  'dy': 0.21},
    {'id': 'FIJ-ORN24x1',           'dx': 0.76,  'dy': 0.43},
    {'id': 'FIV-CHC-M3-12',         'dx': 0.785,  'dy': 0.38},
  ];

  // Hotspots BZL3 — positions à ajuster par l'utilisateur
  static const _hotspotsBZL3 = [
    {'id': 'BZL-031A',              'dx': 0.125, 'dy': 0.945},
    {'id': 'BZL-300',               'dx': 0.39, 'dy': 0.92},
    {'id': 'BZL-301',               'dx': 0.23, 'dy': 0.525},
    {'id': 'BZL-301',               'dx': 0.37, 'dy': 0.45},
    {'id': 'BZL-302',               'dx': 0.53, 'dy': 0.2},
    {'id': 'BZL-303',               'dx': 0.925, 'dy': 0.49},
    {'id': 'BZL-304',               'dx': 0.95, 'dy': 0.46},
    {'id': 'BZL-305',               'dx': 0.96, 'dy': 0.39},
    {'id': 'BZL-306',               'dx': 0.51, 'dy': 0.25},
    {'id': 'BZL-307',               'dx': 0.18, 'dy': 0.64},
    {'id': 'BZL-307',               'dx': 0.41, 'dy': 0.21},
    {'id': 'BZL-308',               'dx': 0.38, 'dy': 0.825},
    {'id': 'BZL-308',               'dx': 0.40, 'dy': 0.245},
    {'id': 'BZL-309',               'dx': 0.84, 'dy': 0.035},
    {'id': 'BZL-310',               'dx': 0.32, 'dy': 0.52},
    {'id': 'BZL-311',               'dx': 0.13, 'dy': 0.525},
    {'id': 'BZL-312',               'dx': 0.48, 'dy': 0.735},
    {'id': 'BZL-313',               'dx': 0.95, 'dy': 0.43},
    {'id': 'BZL-314',               'dx': 0.79, 'dy': 0.075},
    {'id': 'BZL-315',               'dx': 0.935, 'dy': 0.05},
    {'id': 'BZL-AC-104',            'dx': 0.725, 'dy': 0.785},
    {'id': 'BZL-AC-105',            'dx': 0.89, 'dy': 0.72},
    {'id': 'FIJ-ORN-3x1',           'dx': 0.05, 'dy': 0.525},
    {'id': 'FIJ-ORN-3x1',           'dx': 0.16, 'dy': 0.57},
    {'id': 'FIJ-ORN-3.5x1',         'dx': 0.41, 'dy': 0.19},
    {'id': 'FIJ-ORN-16x1.5',        'dx': 0.22, 'dy': 0.48},
    {'id': 'FIJ-ORN-28x1.5',        'dx': 0.23, 'dy': 0.925},
    {'id': 'FIJ-ORS-18x2',          'dx': 0.79, 'dy': 0.13},
    {'id': 'FIT-RBS-626-2RS-I',     'dx': 0.64, 'dy': 0.805},
    {'id': 'FIT-RBS-626-2RS-I',     'dx': 0.80, 'dy': 0.803},
    {'id': 'FIV-BHC-M6-25-Z',       'dx': 0.86, 'dy': 0.785},
    {'id': 'FIV-CHC-M2-06-B',       'dx': 0.38, 'dy': 0.29},
    {'id': 'FIV-CHC-M2-06-B',       'dx': 0.48, 'dy': 0.81},
    {'id': 'FIV-FTO-M3-08-Z',       'dx': 0.33, 'dy': 0.86},
    {'id': 'FIV-FTO-M3-10-Z',       'dx': 0.55, 'dy': 0.15},
    {'id': 'FIV-ROG-06-I',          'dx': 0.615, 'dy': 0.785},
    {'id': 'FTR-CRAV-160VS EM14',   'dx': 0.80, 'dy': 0.50},
    {'id': 'HPS-08E-124',           'dx': 0.48, 'dy': 0.78},
  ];

  OverlayEntry? _overlayEntry;

  Map<String, String>? _findModule(String id) {
    try {
      return widget.modules.firstWhere((m) => m['id'] == id);
    } catch (_) {
      return null;
    }
  }

  void _showPopup(String id, Offset globalPosition) {
    _removePopup();
    final mod = _findModule(id);
    if (mod == null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(children: [
        // Fond transparent pour fermer au clic extérieur
        Positioned.fill(
          child: GestureDetector(
            onTap: _removePopup,
            child: Container(color: Colors.transparent))),

        // Popup positionné près du hotspot
        Positioned(
          left: (globalPosition.dx - 100).clamp(8.0, 200.0),
          top:  (globalPosition.dy - 280).clamp(80.0, 600.0),
          child: GestureDetector(
            onTap: () {}, // absorbe le tap pour ne pas fermer
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.7)),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.8), blurRadius: 20)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Image pièce
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        mod['img'] ?? '',
                        height: 90, width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          color: Colors.white.withOpacity(0.04),
                          child: Icon(Icons.memory,
                            color: const Color(0xFFEAB308).withOpacity(0.4), size: 32)))),
                    const SizedBox(height: 8),
                    Text(mod['nameKey'] != null ? _lang.t(mod['nameKey']!) : id, style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900,
                      fontSize: 12, fontFamily: 'monospace')),
                    if (widget.isPicote && widget.picoteRefs.containsKey(id)) ...[
                      const SizedBox(height: 2),
                      Text(widget.picoteRefs[id]!, style: TextStyle(
                        color: const Color(0xFFEAB308), fontSize: 10,
                        fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                    ],
                    const SizedBox(height: 2),
                    if ((mod['version'] ?? '').isNotEmpty)
                    Text('Version ${mod['version'] ?? ''}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                    const SizedBox(height: 10),
                    // Bouton panier
                    GestureDetector(
                      onTap: () async {
                        _removePopup();
                        await widget.onAddToCart(mod);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAB308),
                          borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_shopping_cart, color: Colors.black, size: 14),
                            SizedBox(width: 6),
                            Text('Ajouter au panier', style: TextStyle(
                              color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
                          ]),
                      ),
                    ),
                  ]),
              ),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removePopup() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBZL1    = widget.bzl == 'BZL1';
    final isBZL3    = widget.bzl == 'BZL3';
    final hotspots  = isBZL1 ? _hotspotsBZL1 : isBZL3 ? _hotspotsBZL3 : _hotspotsBZL2;
    final imgAsset  = isBZL1
        ? 'assets/BZL1/bzl_001_eclate.png'
        : isBZL3
            ? 'assets/BZL3/bzl_003_eclate.png'
            : 'assets/BZL2/bzl_002_eclate.png';
    final ratio     = isBZL1 ? 0.7080 : isBZL3 ? 0.7066 : 0.7043;
    final isBZLSmall = isBZL1 || isBZL3; // taille réduite des hotspots

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = w * ratio;

        return SizedBox(
          width: w, height: h,
          child: Stack(children: [
            // Image fixe — tap pour ouvrir en plein écran
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (dialogCtx) => _FullscreenExplodedDialog(
                  modules: widget.modules,
                  onAddToCart: widget.onAddToCart,
                  hotspots: hotspots,
                  imgAsset: imgAsset,
                  ratio: ratio,
                  isBZL3: isBZLSmall,
                  isPicote: widget.isPicote,
                  picoteRefs: widget.picoteRefs,
                )),
              child: Image.asset(imgAsset,
                width: w, height: h, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black12,
                  child: const Center(child: Icon(Icons.image_not_supported,
                    color: Colors.white24, size: 40))))),

            // Hotspots visibles (jaunes) — à repositionner, puis rendre invisibles
            ...hotspots.map((spot) {
              final dx = spot['dx'] as double;
              final dy = spot['dy'] as double;
              final id = spot['id'] as String;
              if (_findModule(id) == null) return const SizedBox.shrink();
              final hsW = isBZLSmall ? 20.0 : 30.0;
              final hsH = isBZLSmall ?  5.0 :  8.0;

              return Positioned(
                left: w * dx - hsW / 2,
                top:  h * dy - hsH / 2,
                child: GestureDetector(
                  onTapUp: (details) => _showPopup(id, details.globalPosition),
                  child: Container(
                    width: hsW, height: hsH,
                    color: Colors.transparent,
                  )),
              );
            }).toList(),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════
// DIALOG PLEIN ÉCRAN AVEC POPUP INTÉGRÉ
// ══════════════════════════════════════════════════
class _FullscreenExplodedDialog extends StatefulWidget {
  final List<Map<String, String>> modules;
  final Future<void> Function(Map<String, String>) onAddToCart;
  final List<Map<String, Object>> hotspots;
  final String imgAsset;
  final double ratio;
  final bool isBZL3;
  final bool isPicote;
  final Map<String, String> picoteRefs;

  const _FullscreenExplodedDialog({
    required this.modules,
    required this.onAddToCart,
    required this.hotspots,
    required this.imgAsset,
    required this.ratio,
    required this.isBZL3,
    required this.isPicote,
    required this.picoteRefs,
  });

  @override
  State<_FullscreenExplodedDialog> createState() => _FullscreenExplodedDialogState();
}

class _FullscreenExplodedDialogState extends State<_FullscreenExplodedDialog> {
  final _lang = LangService();
  String? _activeId;

  Map<String, String>? _findModule(String id) {
    try {
      return widget.modules.firstWhere((m) => m['id'] == id);
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        // Tap en dehors de l'image → ferme le dialog
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Stack(children: [
            // Image + hotspots dans InteractiveViewer
            Center(
              child: LayoutBuilder(builder: (_, dc) {
                final dw = dc.maxWidth;
                final imgH = dw * widget.ratio;
                return GestureDetector(
                  onTap: () {
                    if (_activeId != null) {
                      setState(() => _activeId = null);
                    }
                  },
                  child: InteractiveViewer(
                    minScale: 0.5, maxScale: 6.0,
                    child: SizedBox(
                      width: dw, height: imgH,
                      child: Stack(children: [
                        Image.asset(widget.imgAsset,
                          width: dw, height: imgH, fit: BoxFit.contain),
                        // Hotspots visibles — à repositionner
                        ...widget.hotspots.map((spot) {
                          final dx = spot['dx'] as double;
                          final dy = spot['dy'] as double;
                          final id = spot['id'] as String;
                          if (_findModule(id) == null) return const SizedBox.shrink();
                          final hsW = widget.isBZL3 ? 20.0 : 30.0;
                          final hsH = widget.isBZL3 ?  5.0 :  8.0;
                          return Positioned(
                            left: dw * dx - hsW / 2,
                            top:  imgH * dy - hsH / 2,
                            child: GestureDetector(
                              onTap: () => setState(() =>
                                _activeId = _activeId == id ? null : id),
                              child: Container(
                                width: hsW, height: hsH,
                                color: Colors.transparent,
                              )),
                          );
                        }).toList(),
                      ]),
                    ),
                  ),
                );
              }),
            ),

            // Popup par-dessus tout dans le dialog
            if (_activeId != null) ...[
              // Fond semi-transparent pour fermer
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _activeId = null),
                  child: Container(color: Colors.transparent))),
              // Popup centré
              Center(
                child: GestureDetector(
                  onTap: () {}, // absorbe tap
                  child: _buildPopup(_activeId!),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildPopup(String id) {
    final mod = _findModule(id);
    if (mod == null) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.7)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 20)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(mod['img'] ?? '',
              height: 100, width: double.infinity, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(height: 60,
                color: Colors.white.withOpacity(0.04),
                child: Icon(Icons.memory,
                  color: const Color(0xFFEAB308).withOpacity(0.4), size: 32)))),
          const SizedBox(height: 10),
          Text(mod['nameKey'] != null ? _lang.t(mod['nameKey']!) : id, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, fontFamily: 'monospace')),
          if (widget.isPicote && widget.picoteRefs.containsKey(id)) ...[
            const SizedBox(height: 2),
            Text(widget.picoteRefs[id]!, style: const TextStyle(
              color: Color(0xFFEAB308), fontSize: 11,
              fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ],
          const SizedBox(height: 2),
          if ((mod['version'] ?? '').isNotEmpty)
          Text('Version ${mod['version'] ?? ''}',
            style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              setState(() => _activeId = null);
              Navigator.pop(context);
              await widget.onAddToCart(mod);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAB308),
                borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_shopping_cart, color: Colors.black, size: 16),
                SizedBox(width: 8),
                Text('Ajouter au panier', style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
