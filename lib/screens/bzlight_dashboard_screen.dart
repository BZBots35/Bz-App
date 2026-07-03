// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/lang_service.dart';
import '../services/auth_service.dart';
import '../services/robot_service.dart';
import '../services/app_roles.dart';
import '../services/bzlight_modules_service.dart';
import '../widgets/lang_selector.dart';
import 'bzlight_modules_screen.dart';
import 'my_robots_screen.dart';
import 'cart_badge.dart';
import 'bz_tutorial.dart';

// ══════════════════════════════════════════════════
// CHARTE GRAPHIQUE "PICOTE" — fond clair, rouge industriel
// ══════════════════════════════════════════════════
class _BzColors {
  static const Color red       = Color(0xFFEAB308);
  static const Color redDark   = Color(0xFFCA9A06);
  static const Color redTint   = Color(0xFF1A1505);
  static const Color solidFill = Color(0xFF1F1F1F);
  static const Color bg        = Color(0xFF0A0A0F);
  static const Color surface   = Color(0xFF12121A);
  static const Color border    = Color(0x14FFFFFF);
  static const Color textMain  = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFB0B0B8);
  static const Color textHint  = Color(0xFF6B6B75);
}

class BzLightDashboardScreen extends StatefulWidget {
  final String serial;
  final int    serie;
  final String year;
  final int    number;
  final String company;

  const BzLightDashboardScreen({super.key,
    required this.serial, required this.serie, required this.year,
    required this.number, required this.company});

  @override
  State<BzLightDashboardScreen> createState() => _BzLightDashboardScreenState();
}

class _BzLightDashboardScreenState extends State<BzLightDashboardScreen> {
  final _lang        = LangService();
  final _auth        = AuthService();
  final _robots      = RobotService();
  final _modulesService = BzlightModulesService();
  final _tutorialKey = GlobalKey<BzTutorialState>();
  String _userRole   = '';

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadRole();
  }

  Future<void> _loadRole() async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    final role = await _auth.getUserRole(user.$id);
    if (mounted) setState(() => _userRole = role);
  }

  bool get _canSeeRepairSheet =>
    _userRole == AppRoles.superAdmin ||
    _userRole == AppRoles.admin ||
    _userRole == AppRoles.distributeur;

  Future<void> _openRepairSheet() async {
    final doc = await _robots.getRobotBySerial(widget.serial);
    if (doc == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RobotHistoryScreen(doc: doc, userRole: _userRole)));
  }

  List<TutorialStep> get _tutorialSteps => [
    TutorialStep(title: 'Série du robot', description: 'Ce grand chiffre indique la série de votre robot BzLight.', targetOffset: const Offset(0.5, 0.18), targetSize: 40),
    TutorialStep(title: 'Numéro de référence', description: 'Ce code unique est l\'identifiant complet de votre robot. Gardez-le précieusement.', targetOffset: const Offset(0.5, 0.26), targetSize: 30),
    TutorialStep(title: 'Composants cliquables', description: 'Les cercles animés sont des boutons ! Appuyez dessus pour voir et commander les modules de chaque partie du robot.', targetOffset: const Offset(0.22, 0.58), targetSize: 22),
  ];

  static const _modules = {
    'BZL1': [
      {'id': 'BZL-011',               'img': 'assets/BZL1/BZL-011.png'},
      {'id': 'BZL-012',               'img': 'assets/BZL1/BZL-012.png'},
      {'id': 'BZL-013',               'img': 'assets/BZL1/BZL-013.png'},
      {'id': 'BZL-100',               'img': 'assets/BZL1/BZL-100.png'},
      {'id': 'BZL-101',               'img': 'assets/BZL1/BZL-101.png'},
      {'id': 'BZL-102',               'img': 'assets/BZL1/BZL-102.png'},
      {'id': 'BZL-103',               'img': 'assets/BZL1/BZL-103.png'},
      {'id': 'BZL-104',               'img': 'assets/BZL1/BZL-104.png'},
      {'id': 'BZL-105',               'img': 'assets/BZL1/BZL-105.png'},
      {'id': 'BZL-106',               'img': 'assets/BZL1/BZL-106.png'},
      {'id': 'BZL-107',               'img': 'assets/BZL1/BZL-107.png'},
      {'id': 'BZL-117',               'img': 'assets/BZL1/BZL-117.png'},
      {'id': 'FIG-CYL-04-10-I',       'img': 'assets/BZL1/FIG-CYL-04-10-I.png'},
      {'id': 'FIJ-ORN-3x1',           'img': 'assets/BZL1/FIJ-ORN-3x1.png'},
      {'id': 'FIJ-ORN-28x1.5',        'img': 'assets/BZL1/FIJ-ORN-28x1.5.png'},
      {'id': 'FIJ-ORN-65x1',          'img': 'assets/BZL1/FIJ-ORN-65x1.png'},
      {'id': 'FIQ-RT-7.62-1.4-57.1',  'img': 'assets/BZL1/FIQ-RT-7.62-1.4-57.1.png'},
      {'id': 'FIT-RBS-626',           'img': 'assets/BZL1/FIT-RBS-626.png'},
      {'id': 'FIV-CTO-M3-10-Z',       'img': 'assets/BZL1/FIV-CTO-M3-10-Z.png'},
      {'id': 'FIV-CTO-M3-20-Z',       'img': 'assets/BZL1/FIV-CTO-M3-20-Z.png'},
      {'id': 'FIV-CTO-M4-16-Z',       'img': 'assets/BZL1/FIV-CTO-M4-16-Z.png'},
      {'id': 'FIV-CTO-M4-20-Z',       'img': 'assets/BZL1/FIV-CTO-M4-20-Z.png'},
      {'id': 'FIV-FTO-M3-08-Z',       'img': 'assets/BZL1/FIV-FTO-M3-08-Z.png'},
      {'id': 'FIV-HC-M4-20-Z',        'img': 'assets/BZL1/FIV-HC-M4-20-Z.png'},
      {'id': 'FIV-HCB-M6-14',         'img': 'assets/BZL1/FIV-HCB-M6-14.png'},
      {'id': 'FIV-ROG-03-I',          'img': 'assets/BZL1/FIV-ROG-03-I.png'},
      {'id': 'FIV-ROG-04-I',          'img': 'assets/BZL1/FIV-ROG-04-I.png'},
      {'id': 'FIV-ROG-05',            'img': 'assets/BZL1/FIV-ROG-05.png'},
      {'id': 'ROCOL-SAPPHIRE',         'img': 'assets/BZL1/ROCOL-SAPPHIRE.png', 'nameKey': 'rocolSapphire'},
    ],
    'BZL2': [
      {'id': 'BZL-021-A',             'version': '2', 'img': 'assets/BZL2/BZL-021-A.png'},
      {'id': 'BZL-021-B',             'version': '2', 'img': 'assets/BZL2/BZL-021-B.png'},
      {'id': 'BZL-201',                'version': '1', 'img': 'assets/BZL2/BZL201.png'},
      {'id': 'BZL-202',                'version': '1', 'img': 'assets/BZL2/BZL202.png'},
      {'id': 'BZL-203',                'version': '1', 'img': 'assets/BZL2/BZL203.png'},
      {'id': 'BZL-204',                'version': '1', 'img': 'assets/BZL2/BZL204.png'},
      {'id': 'BZL-206',                'version': '1', 'img': 'assets/BZL2/BZL206.png'},
      {'id': 'FIJ-ORN-2.8x1.5',       'version': '1', 'img': 'assets/BZL2/FIJ-ORN-2.8x1.5.png'},
      {'id': 'FIJ-ORN-11x1.5',        'version': '1', 'img': 'assets/BZL2/FIJ-ORN-11x1.5.png'},
      {'id': 'FIJ-ORN-28x1.5',        'version': '1', 'img': 'assets/BZL2/FIJ-ORN-28x1.5.png'},
      {'id': 'FIQ-RC-15.24-1.4-38.1', 'version': '1', 'img': 'assets/BZL2/FIQ-RC-15.24-1.4-38.1.png'},
      {'id': 'FIV-CTO-M3-10-Z',       'version': '1', 'img': 'assets/BZL2/FIV-CTO-M3-10-Z.png'},
      {'id': 'FIV-FTO-M3-08-Z',       'version': '1', 'img': 'assets/BZL2/FIV-FTO-M3-08-Z.png'},
      {'id': 'FIV-ROG-03-I',          'version': '1', 'img': 'assets/BZL2/FIV-ROG-03-I.png'},
      {'id': 'FIV-CHC-M3-20',         'version': '1', 'img': 'assets/BZL2/FIV-CHC-M3-20.png'},
      {'id': 'FIJ-ORN24x1',           'version': '1', 'img': 'assets/BZL2/FIJ-ORN24x1.png'},
      {'id': 'FIV-CHC-M3-12',         'version': '1', 'img': 'assets/BZL2/FIV-CHC-M3-12.png'},
    ],
    'BZL3': [
      {'id': 'BZL-031A',              'img': 'assets/BZL3/BZL-031A.png'},
      {'id': 'BZL-300',               'img': 'assets/BZL3/BZL-300.png'},
      {'id': 'BZL-301',               'img': 'assets/BZL3/BZL-301.png'},
      {'id': 'BZL-302',               'img': 'assets/BZL3/BZL-302.png'},
      {'id': 'BZL-303',               'img': 'assets/BZL3/BZL-303.png'},
      {'id': 'BZL-304',               'img': 'assets/BZL3/BZL-304.png'},
      {'id': 'BZL-305',               'img': 'assets/BZL3/BZL-305.png'},
      {'id': 'BZL-306',               'img': 'assets/BZL3/BZL-306.png'},
      {'id': 'BZL-307',               'img': 'assets/BZL3/BZL-307.png'},
      {'id': 'BZL-308',               'img': 'assets/BZL3/BZL-308.png'},
      {'id': 'BZL-309',               'img': 'assets/BZL3/BZL-309.png'},
      {'id': 'BZL-310',               'img': 'assets/BZL3/BZL-310.png'},
      {'id': 'BZL-311',               'img': 'assets/BZL3/BZL-311.png'},
      {'id': 'BZL-312',               'img': 'assets/BZL3/BZL-312.png'},
      {'id': 'BZL-313',               'img': 'assets/BZL3/BZL-313.png'},
      {'id': 'BZL-314',               'img': 'assets/BZL3/BZL-314.png'},
      {'id': 'BZL-315',               'img': 'assets/BZL3/BZL-315.png'},
      {'id': 'BZL-AC-104',            'img': 'assets/BZL3/BZL-AC-104.png'},
      {'id': 'BZL-AC-105',            'img': 'assets/BZL3/BZL-AC-105.png'},
      {'id': 'FIJ-ORN-3x1',           'img': 'assets/BZL3/FIJ-ORN-3x1.png'},
      {'id': 'FIJ-ORN-3.5x1',         'img': 'assets/BZL3/FIJ-ORN-3.5x1.png'},
      {'id': 'FIJ-ORN-16x1.5',        'img': 'assets/BZL3/FIJ-ORN-16x1.5.png'},
      {'id': 'FIJ-ORN-28x1.5',        'img': 'assets/BZL3/FIJ-ORN-28x1.5.png'},
      {'id': 'FIJ-ORS-18x2',          'img': 'assets/BZL3/FIJ-ORS-18x2.png'},
      {'id': 'FIT-RBS-626-2RS-I',     'img': 'assets/BZL3/FIT-RBS-626-2RS-I.png'},
      {'id': 'FIV-BHC-M6-25-Z',       'img': 'assets/BZL3/FIV-BHC-M6-25-Z.png'},
      {'id': 'FIV-CHC-M2-06-B',       'img': 'assets/BZL3/FIV-CHC-M2-06-B.png'},
      {'id': 'FIV-FTO-M3-08-Z',       'img': 'assets/BZL3/FIV-FTO-M3-08-Z.png'},
      {'id': 'FIV-FTO-M3-10-Z',       'img': 'assets/BZL3/FIV-FTO-M3-10-Z.png'},
      {'id': 'FIV-ROG-06-I',          'img': 'assets/BZL3/FIV-ROG-06-I.png'},
      {'id': 'FTR-CRAV-160VS EM14',   'img': 'assets/BZL3/FTR-CRAV-160VS-EM14.png'},
      {'id': 'HPS-08E-124',           'img': 'assets/BZL3/HPS-08E-124.png'},
    ],
    'BZL4': <Map<String, String>>[],
  };

  // Construit le label avec numéro de série
  String _hotspotLabel(String bzl) {
    final num = widget.number.toString().padLeft(5, '0');
    return '$bzl-${widget.year}-$num';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _BzColors.bg,
      appBar: AppBar(
        backgroundColor: _BzColors.solidFill,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: const Text('BZLIGHT — DASHBOARD',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
            letterSpacing: 1.5, fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white70, size: 20), onPressed: () => _tutorialKey.currentState?.show()),
          CartBadge(), LangSelector(), const SizedBox(width: 8)],
      ),
      body: BzTutorial(key: _tutorialKey, tutorialKey: 'bzlight_dashboard', steps: _tutorialSteps, child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Série validée
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _BzColors.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _BzColors.red.withOpacity(0.3)),
              boxShadow: [BoxShadow(
                color: _BzColors.red.withOpacity(0.08),
                blurRadius: 20)],
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  '${_lang.t("serieValidated")} ${widget.serie}',
                  style: const TextStyle(color: _BzColors.textMain,
                    fontSize: 36, fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                Container(width: 32, height: 32,
                  decoration: const BoxDecoration(
                    color: _BzColors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.black, size: 18)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _BzColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _BzColors.border)),
                child: Text(widget.serial,
                  style: const TextStyle(color: _BzColors.textMain, fontSize: 16,
                    fontWeight: FontWeight.w900, letterSpacing: 3,
                    fontFamily: 'monospace')),
              ),
              if (widget.company.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(widget.company,
                  style: const TextStyle(color: _BzColors.textHint, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(_lang.t('components')),
          const SizedBox(height: 14),
          _buildInteractiveRobot(context),
          if (_canSeeRepairSheet) ...[
            const SizedBox(height: 16),
            _buildSectionTitle(_lang.t('repairSheet')),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _openRepairSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _BzColors.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _BzColors.red.withOpacity(0.3))),
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _BzColors.redTint,
                      borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.build_circle_outlined,
                      color: _BzColors.red, size: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_lang.t('repairSheet'), style: const TextStyle(
                      color: _BzColors.textMain, fontWeight: FontWeight.w900,
                      fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(_lang.t('repairSheetHint'), style: const TextStyle(
                      color: _BzColors.textHint, fontSize: 11)),
                  ])),
                  const Icon(Icons.chevron_right, color: _BzColors.textHint, size: 20),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 30),
        ]),
      )),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(
            color: _BzColors.red, width: 3))),
        child: Text(title, style: const TextStyle(color: _BzColors.textMuted,
          fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
      ),
    );
  }

  Widget _buildInteractiveRobot(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _BzColors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _BzColors.border)),
      child: Column(children: [
        LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = w * 0.42;
          return SizedBox(width: w, height: h,
            child: Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/bzlight_render.png',
                  width: w, height: h, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: _BzColors.surface,
                    child: Center(child: Icon(Icons.flash_on,
                      color: _BzColors.red.withOpacity(0.3),
                      size: 60))))),
              _Hotspot(
                label: _hotspotLabel('BZL1'),
                relLeft: 0.17, relTop: 0.55, containerH: h,
                labelAbove: false,
                onTap: () => _openModules(context, 'BZL1')),
              _Hotspot(
                label: _hotspotLabel('BZL2'),
                relLeft: 0.36, relTop: 0.55, containerH: h,
                labelAbove: false,
                onTap: () => _openModules(context, 'BZL2')),
              _Hotspot(
                label: _hotspotLabel('BZL3'),
                relLeft: 0.62, relTop: 0.42, containerH: h,
                labelAbove: false,
                onTap: () => _openModules(context, 'BZL3')),
              _Hotspot(
                label: _hotspotLabel('BZL4'),
                relLeft: 0.33, relTop: 0.37, containerH: h,
                labelAbove: true, // label au-dessus pour BZL4
                onTap: () => _openModules(context, 'BZL4')),
            ]));
        }),
        const SizedBox(height: 10),
        Text(_lang.t('tapHotspot'),
          style: const TextStyle(color: _BzColors.textHint, fontSize: 10)),
      ]),
    );
  }

  void _openModules(BuildContext context, String bzl) async {
    final staticMods = _modules[bzl] ?? [];
    // Récupère les versions à jour depuis Appwrite (docId + version par sous-module)
    final liveVersions = await _modulesService.getModulesByBzl(bzl);
    final versionById = {
      for (final v in liveVersions) v['id']!: v,
    };
    final mergedMods = staticMods.map((m) {
      final live = versionById[m['id']];
      return {
        ...m,
        if (live != null) 'version': live['version'] ?? m['version'] ?? '',
        if (live != null) 'docId'  : live['docId'] ?? '',
      };
    }).toList();
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BzLightModulesScreen(
        bzl: bzl,
        robotSerial: widget.serial,
        modules: mergedMods,
        userRole: _userRole)));
  }
}

// ── Hotspot ───────────────────────────────────────
class _Hotspot extends StatefulWidget {
  final String label;
  final double relLeft, relTop, containerH;
  final VoidCallback onTap;
  final bool labelAbove;

  const _Hotspot({
    required this.label,
    required this.relLeft,
    required this.relTop,
    required this.containerH,
    required this.onTap,
    this.labelAbove = false,
  });

  @override
  State<_Hotspot> createState() => _HotspotState();
}

class _HotspotState extends State<_Hotspot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 64;
    return Positioned(
      left: w * widget.relLeft - 14,
      top:  widget.containerH * widget.relTop - 14,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(width: 40, height: 40,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
           children: [
          
            // Onde animée — rouge
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Transform.scale(
                scale: 1 + _anim.value * 0.7,
                child: Container(width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _BzColors.red.withOpacity(
                      0.45 * (1 - _anim.value)))))),

            // Cercle central — transparent avec bordure rouge
            Container(width: 13, height: 13,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: _BzColors.red, width: 2),
                boxShadow: [BoxShadow(
                  color: _BzColors.red.withOpacity(0.4),
                  blurRadius: 6)])),

            // Label — au-dessus ou en-dessous selon labelAbove
            Positioned(
              top:    widget.labelAbove ? null : 24,
              bottom: widget.labelAbove ? 24  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _BzColors.red.withOpacity(0.5))),
                child: Text(widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 6,
                    fontWeight: FontWeight.w900)))),
          ])),
      ),
    );
  }
}


