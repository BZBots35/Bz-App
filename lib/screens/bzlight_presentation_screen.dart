// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import '../services/cart_service.dart';
import '../services/robot_service.dart';
import 'my_robots_screen.dart';
import 'bzlight_dashboard_screen.dart';
import '../widgets/lang_selector.dart';
import 'cart_badge.dart';
import 'bz_tutorial.dart';
import 'bzlight_screen.dart';

// ══════════════════════════════════════════════════
// CHARTE GRAPHIQUE "PICOTE" — fond clair, rouge industriel
// ══════════════════════════════════════════════════
class BzColors {
  static const Color red       = Color(0xFFEAB308); // jaune signature (accents, texte, bordures)
  static const Color redDark   = Color(0xFFCA9A06); // jaune pressé/hover
  static const Color redTint   = Color(0xFF1A1505); // fond très sombre teinté pour badges/icônes
  static const Color solidFill = Color(0xFF1F1F1F); // fond plein gris (AppBar, gros CTA) — jamais de texte blanc sur jaune
  static const Color bg        = Color(0xFF0A0A0F); // fond principal de l'écran
  static const Color surface   = Color(0xFF12121A); // cartes / surfaces légèrement éclaircies
  static const Color border    = Color(0x14FFFFFF); // bordures fines (blanc 8% opacité)
  static const Color textMain  = Color(0xFFFFFFFF); // texte principal
  static const Color textMuted = Color(0xFFB0B0B8); // texte secondaire
  static const Color textHint  = Color(0xFF6B6B75); // texte tertiaire / hints
}

class BzLightPresentationScreen extends StatefulWidget {
  const BzLightPresentationScreen({super.key});
  @override
  State<BzLightPresentationScreen> createState() => _BzLightPresentationScreenState();
}

class _BzLightPresentationScreenState extends State<BzLightPresentationScreen>
    with SingleTickerProviderStateMixin {
  final _lang        = LangService();
  final _auth        = AuthService();
  final _robots      = RobotService();
  late TabController _tabController;
  final _tutorialKey = GlobalKey<BzTutorialState>();

  List<Map<String, dynamic>> _robotList = [];
  String? _selectedSerial;
  String  _userRole = '';
  bool    _isRobotMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadRobots();
  }

  Future<void> _loadRobots() async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    final role    = await _auth.getUserRole(user.$id);
    final company = await _auth.getUserCompany(user.$id);
    List docs;
    if (role == AppRoles.superAdmin || role == AppRoles.admin) {
      docs = await _robots.getAllRobots();
    } else {
      if (company.isEmpty) return;
      docs = await _robots.getCompanyRobots(company);
    }
    if (mounted) {
      setState(() {
        _userRole    = role;
        _robotList   = docs.map((d) => d.data as Map<String, dynamic>).toList();
        if (_robotList.isNotEmpty) _selectedSerial = _robotList.first['serial'] as String;
      });
    }
  }

  Widget _buildDynamicRobotSelector() {
    if (_robotList.isEmpty) return const SizedBox.shrink();
    final currentRobot = _robotList.firstWhere(
      (r) => r['serial'] == _selectedSerial,
      orElse: () => {'serial': '', 'name': ''},
    );
    final serial = currentRobot['serial'] as String? ?? _selectedSerial ?? '';

    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () => setState(() => _isRobotMenuOpen = !_isRobotMenuOpen),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(serial, style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            Icon(_isRobotMenuOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: Colors.white),
          ]),
        ),
      ),
      if (_isRobotMenuOpen) ...[
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            color: BzColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BzColors.border)),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(children: _robotList.map((robot) {
              final s = robot['serial'] as String;
              final isSelected = s == _selectedSerial;
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedSerial = s;
                    _isRobotMenuOpen = false;
                  });
                  _navigateToDashboard(s);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: isSelected ? BzColors.redTint : Colors.transparent,
                  child: Text(s, textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? BzColors.red : BzColors.textMuted,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12, fontFamily: 'monospace')),
                ),
              );
            }).toList()),
          ),
        ),
      ],
    ]);
  }

  void _navigateToDashboard(String serial) {
    final robot = _robotList.firstWhere((r) => r['serial'] == serial);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BzLightDashboardScreen(
        serial:  serial,
        serie:   robot['serie'] as int,
        year:    robot['year'] as String,
        number:  robot['number'] as int,
        company: robot['company'] as String? ?? '',
      )));
  }

  List<TutorialStep> get _tutorialSteps => [
    TutorialStep(
      title: _lang.t('tutPresentTitle'),
      description: _lang.t('tutPresentDesc'),
      targetOffset: const Offset(0.25, 0.32),
      targetSize: 55,
      onBefore: () {
        _tabController.animateTo(0);
        _PresentationTab.scrollTo(0);
      }),
    TutorialStep(
      title: _lang.t('tutAdvantagesTitle'),
      description: _lang.t('tutAdvantagesDesc'),
      targetOffset: const Offset(0.25, 0.3),
      targetSize: 55,
      onBefore: () {
        _tabController.animateTo(0);
        _PresentationTab.scrollTo(300);
      }),
    TutorialStep(
      title: _lang.t('tutSpecsTitle'),
      description: _lang.t('tutSpecsDesc'),
      targetOffset: const Offset(0.25, 0.55),
      targetSize: 55,
      onBefore: () {
        _tabController.animateTo(0);
        Future.delayed(const Duration(milliseconds: 300), () =>
          _PresentationTab.scrollTo(900));
      }),
    TutorialStep(
      title: _lang.t('tutDocsTitle'),
      description: _lang.t('tutDocsDesc'),
      targetOffset: const Offset(0.5, 0.5),
      targetSize: 45,
      onBefore: () => _tabController.animateTo(2)),
    TutorialStep(
      title: _lang.t('tutContactTitle'),
      description: _lang.t('tutContactDesc'),
      targetOffset: const Offset(0.2, 0.69),
      targetSize: 45,
      onBefore: () => _tabController.animateTo(2)),
    TutorialStep(
      title: _lang.t('tutDiagTitle'),
      description: _lang.t('tutDiagDesc'),
      targetOffset: const Offset(0.5, 0.35),
      targetSize: 45,
      onBefore: () => _tabController.animateTo(3)),
  ];

  List<Map<String, dynamic>> get _tabs => [
    {'label': _lang.t('presentation'), 'icon': Icons.info_outline},
    {'label': _lang.t('videos'),       'icon': Icons.play_circle_outline},
    {'label': _lang.t('docsContact'),  'icon': Icons.folder_outlined},
    {'label': _lang.t('diagnostic'),   'icon': Icons.build_outlined},
    {'label': _lang.t('casEmploi'),    'icon': Icons.work_outline},
  ];

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  
Future<void> _handleAccessRobot(BuildContext context) async {
  final auth   = AuthService();
  final robots = RobotService();
  final user   = await auth.getCurrentUser();
  if (user == null) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BzLightScreen()));
    return;
  }
  // Récupère l'entreprise de l'utilisateur connecté
  final company = await auth.getUserCompany(user.$id);
  if (company.isEmpty) {
    // Pas d'entreprise renseignée → écran d'auth pour enregistrer un robot
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BzLightScreen()));
    }
    return;
  }
  // Filtre par entreprise → l'utilisateur voit TOUS les robots de sa société
  final list = await robots.getCompanyRobots(company);
  if (list.isEmpty) {
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BzLightScreen()));
    }
  } else {
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRobotsScreen()));
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BzColors.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_isRobotMenuOpen) setState(() => _isRobotMenuOpen = false);
        },
        child: BzTutorial(key: _tutorialKey, tutorialKey: 'bzlight_presentation', steps: _tutorialSteps, child: NestedScrollView(
          headerSliverBuilder: (_, __) {
            final topPadding = MediaQuery.of(context).padding.top +
                (_isRobotMenuOpen ? 180.0 : kToolbarHeight);
            return [
              SliverAppBar(
                pinned: true,
                snap: false,
                floating: false,
                expandedHeight: _isRobotMenuOpen ? 380.0 : 280.0,
                toolbarHeight: _isRobotMenuOpen ? 180.0 : kToolbarHeight,
                backgroundColor: BzColors.solidFill,
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context)),
                title: _buildDynamicRobotSelector(),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const BzLightScreen()));
                      _loadRobots();
                    }),
                  IconButton(icon: const Icon(Icons.help_outline, color: Colors.white70, size: 20), onPressed: () => _tutorialKey.currentState?.show()),
                  CartBadge(), LangSelector(), const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: Stack(children: [
                    Positioned(
                      top: topPadding,
                      bottom: 48,
                      left: 0,
                      right: 0,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.asset('assets/animations/bzlight_intro.webp', fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: BzColors.solidFill,
                            child: Center(child: Icon(Icons.flash_on,
                              color: Colors.white.withOpacity(0.25), size: 80)))),
                        Container(decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black], stops: [0.4, 1.0]))),
                      ]),
                    ),
                  ]),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Container(
                    color: BzColors.bg,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: false,
                      indicatorColor: BzColors.red,
                      indicatorWeight: 2,
                      labelColor: BzColors.red,
                      unselectedLabelColor: BzColors.textHint,
                      labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      tabAlignment: TabAlignment.fill,
                      tabs: (_tabs as List<Map<String, dynamic>>).map((t) =>
                        Tab(icon: Icon(t['icon'] as IconData, size: 18),
                            text: t['label'] as String,
                            iconMargin: const EdgeInsets.only(bottom: 2))).toList(),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _PresentationTab(),
              _VideosTab(),
              _DocsContactTab(),
              _DiagnosticTab(),
              _CasEmploiTab(),
            ],
          ),
        )),
      ),
    );
  }
}


class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: BzColors.bg,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}


// ══════════════════════════════════════════════════
// ACCORDÉON AVANTAGES
// ══════════════════════════════════════════════════
class _AdvantagesAccordion extends StatefulWidget {
  final List<Map<String, dynamic>> advantages;
  const _AdvantagesAccordion({required this.advantages});
  @override
  State<_AdvantagesAccordion> createState() => _AdvantagesAccordionState();
}

class _AdvantagesAccordionState extends State<_AdvantagesAccordion> {
  int? _openIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BzColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BzColors.border)),
      child: Column(
        children: widget.advantages.asMap().entries.map((e) {
          final i    = e.key;
          final a    = e.value;
          final isOpen = _openIndex == i;
          final isLast = i == widget.advantages.length - 1;
          return Column(children: [
            GestureDetector(
              onTap: () => setState(() => _openIndex = isOpen ? null : i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: (!isLast || isOpen)
                    ? Border(bottom: BorderSide(
                        color: isOpen
                          ? BzColors.red.withOpacity(0.25)
                          : BzColors.border))
                    : null),
                child: Row(children: [
                  // Icône
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: isOpen ? BzColors.redTint : BzColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: isOpen
                        ? Border.all(color: BzColors.red.withOpacity(0.3))
                        : Border.all(color: BzColors.border)),
                    child: Icon(a['icon'] as IconData,
                      color: BzColors.red, size: 16)),
                  const SizedBox(width: 12),
                  // Titre
                  Expanded(
                    child: Text(a['title'] as String,
                      style: TextStyle(
                        color: isOpen ? BzColors.red : BzColors.textMain,
                        fontWeight: FontWeight.w700, fontSize: 13))),
                  // Flèche
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                      color: isOpen
                        ? BzColors.red
                        : BzColors.textHint,
                      size: 20)),
                ]),
              ),
            ),
            // Contenu déployé
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: BzColors.surface,
                  border: !isLast
                    ? Border(bottom: BorderSide(
                        color: BzColors.border))
                    : null),
                child: Text(a['desc'] as String,
                  style: const TextStyle(
                    color: BzColors.textMuted,
                    fontSize: 12, height: 1.6))),
              crossFadeState: isOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200)),
          ]);
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ONGLET 1 — PRÉSENTATION
// ══════════════════════════════════════════════════
class _PresentationTab extends StatefulWidget {
  static final GlobalKey<_PresentationTabState> tabKey = GlobalKey<_PresentationTabState>();

  _PresentationTab() : super(key: tabKey);

  static void scrollTo(double offset) {
    tabKey.currentState?._scrollTo(offset);
  }

  @override
  State<_PresentationTab> createState() => _PresentationTabState();
}

class _PresentationTabState extends State<_PresentationTab> {
  final _lang = LangService();

  void _scrollTo(double offset) {
    final ctrl = PrimaryScrollController.of(context);
    if (ctrl.hasClients) {
      ctrl.animateTo(offset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut);
    }
  }

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lang;
    final advantages = [
      {'icon': Icons.build_outlined,    'title': l.t('simplified'),  'desc': l.t('simplifiedDesc')},
      {'icon': Icons.tune,              'title': l.t('practical'),   'desc': l.t('practicalDesc')},
      {'icon': Icons.bolt,              'title': l.t('powerful'),    'desc': l.t('powerfulDesc')},
      {'icon': Icons.videocam_outlined, 'title': l.t('intCamera'),   'desc': l.t('intCameraDesc')},
      {'icon': Icons.luggage,           'title': l.t('compact2'),    'desc': l.t('compactDesc')},
      {'icon': Icons.layers_outlined,   'title': l.t('multiUse'),    'desc': l.t('multiUseDesc')},
    ];

    final specs = [
      [l.t('pipeDiam'),    'DN100 — DN150'],
      [l.t('rangeStd'),    '16 m'],
      [l.t('rangeExt'),    '26 m'],
      [l.t('curves2'),     '45° — 90°'],
      [l.t('weightBzl'),   '2,45 kg'],
      [l.t('airPressure'), '8/10 Bar'],
      [l.t('airVolume'),   '150 l/min'],
      [l.t('dimensions'),  '420 × 85 × 65 mm'],
    ];

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Description
      _sectionTitle(l.t('description'), Icons.info_outline),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: BzColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BzColors.border)),
        child: Text(l.t('bzDescLong'),
          style: const TextStyle(color: BzColors.textMuted, fontSize: 13, height: 1.6))),
      const SizedBox(height: 20),

      // Avantages
      _sectionTitle(l.t('advantages'), Icons.star_outline),
      const SizedBox(height: 10),
      _AdvantagesAccordion(advantages: advantages),
      const SizedBox(height: 20),

      // Specs
      _sectionTitle(l.t('specs'), Icons.settings_outlined),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: BzColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BzColors.border)),
        child: Column(
          children: specs.asMap().entries.map((e) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: e.key < specs.length - 1
                  ? Border(bottom: BorderSide(color: BzColors.border))
                  : null),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.value[0], style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
                  Text(e.value[1], style: const TextStyle(color: BzColors.textMain,
                    fontSize: 12, fontWeight: FontWeight.w700)),
                ]))
          ).toList(),
        )),
      const SizedBox(height: 20),
    ]);
  }
}

// ══════════════════════════════════════════════════
// ONGLET 2 — VIDÉOS
// ══════════════════════════════════════════════════
class _VideosTab extends StatefulWidget {
  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _cleaningOpen = false;
  bool _repairOpen   = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = LangService();
    final cleaningVideos = [
      {'title': l.t('cleaning'),     'videoId': 'KrNA8CR_x9E'},
      {'title': l.t('deepCleaning'), 'videoId': 'eARLGuMHqLU'},
    ];
    final repairVideos = [
      {'title': 'Camera module replacement',    'videoId': 'fwQJbY4NCog'},
      {'title': 'Clean and grease the piston',  'videoId': 'LxCpT7f6qR8'},
      {'title': 'Rear module replacement',      'videoId': 'nrQGiUvbrcY'},
      {'title': 'Replace the rear casing',      'videoId': 'LTiIcKyBDu8'},
    ];

    final isSearching = _query.isNotEmpty;
    final cleaningFiltered = cleaningVideos.where((v) => v['title']!.toLowerCase().contains(_query)).toList();
    final repairFiltered   = repairVideos.where((v) => v['title']!.toLowerCase().contains(_query)).toList();
    final noResultsAtAll = isSearching && cleaningFiltered.isEmpty && repairFiltered.isEmpty;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Barre de recherche
      TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: BzColors.textMain, fontSize: 13),
        decoration: InputDecoration(
          hintText: l.t('videosSearchHint'),
          hintStyle: const TextStyle(color: BzColors.textHint, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: BzColors.textHint, size: 20),
          suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, color: BzColors.textHint, size: 18),
                onPressed: () => _searchCtrl.clear())
            : null,
          filled: true,
          fillColor: BzColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: BzColors.border)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: BzColors.border)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: BzColors.red)),
        ),
      ),
      const SizedBox(height: 16),

      if (noResultsAtAll)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text(l.t('videosNoResults'),
            style: const TextStyle(color: BzColors.textHint, fontSize: 13)))),

      // Catégorie : Nettoyage
      if (!isSearching || cleaningFiltered.isNotEmpty) ...[
        _buildCategoryHeader(
          title: l.t('cleaning'),
          icon: Icons.cleaning_services_outlined,
          count: cleaningFiltered.length,
          isOpen: isSearching ? true : _cleaningOpen,
          onTap: isSearching ? null : () => setState(() => _cleaningOpen = !_cleaningOpen),
        ),
        if (isSearching ? true : _cleaningOpen) ...[
          const SizedBox(height: 12),
          _buildVideoGrid(context, cleaningFiltered),
        ],
        const SizedBox(height: 16),
      ],

      // Catégorie : Réparations
      if (!isSearching || repairFiltered.isNotEmpty) ...[
        _buildCategoryHeader(
          title: l.t('videosCategoryRepair'),
          icon: Icons.build_circle_outlined,
          count: repairFiltered.length,
          isOpen: isSearching ? true : _repairOpen,
          onTap: isSearching ? null : () => setState(() => _repairOpen = !_repairOpen),
        ),
        if (isSearching ? true : _repairOpen) ...[
          const SizedBox(height: 12),
          _buildVideoGrid(context, repairFiltered),
        ],
      ],
    ]);
  }

  Widget _buildCategoryHeader({
    required String title,
    required IconData icon,
    required int count,
    required bool isOpen,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: BzColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOpen ? BzColors.red.withOpacity(0.4) : BzColors.border)),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: BzColors.redTint,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: BzColors.red, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
            style: const TextStyle(color: BzColors.textMain,
              fontWeight: FontWeight.w800, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: BzColors.border,
              borderRadius: BorderRadius.circular(20)),
            child: Text('$count',
              style: const TextStyle(color: BzColors.textMuted,
                fontSize: 11, fontWeight: FontWeight.w700))),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down,
                color: BzColors.textHint, size: 20)),
          ],
        ]),
      ),
    );
  }

  Widget _buildVideoGrid(BuildContext context, List<Map<String, String>> videos) {
    if (videos.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: videos.length,
      itemBuilder: (_, i) => _buildVideoCard(context, videos[i]),
    );
  }

  Widget _buildVideoCard(BuildContext context, Map<String, String> v) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => _VideoPlayerScreen(
          title: v['title']!, videoId: v['videoId']!))),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BzColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(fit: StackFit.expand, children: [
                Image.network(
                  'https://img.youtube.com/vi/${v['videoId']}/hqdefault.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: BzColors.surface)),
                Center(child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: BzColors.red,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: BzColors.red.withOpacity(0.4),
                      blurRadius: 10)]),
                  child: const Icon(Icons.play_arrow, color: Colors.black, size: 20))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(v['title']!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BzColors.textMain,
                fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.3)),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ONGLET 3 — DOCS & CONTACT
// ══════════════════════════════════════════════════
class _DocsContactTab extends StatefulWidget {
  @override
  State<_DocsContactTab> createState() => _DocsContactTabState();
}

class _DocsContactTabState extends State<_DocsContactTab> {
  final _lang = LangService();
  final _auth = AuthService();
  String _reseller = '';
  bool _loadingReseller = true;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadReseller();
  }

  Future<void> _loadReseller() async {
    final user = await _auth.getCurrentUser();
    if (user != null) {
      final reseller = await _auth.getUserReseller(user.$id);
      if (mounted) setState(() {
        _reseller = reseller;
        _loadingReseller = false;
      });
    } else if (mounted) {
      setState(() => _loadingReseller = false);
    }
  }

  // Retourne le bon fichier PDF selon la langue active
  String _quickGuideFile() {
    return _lang.currentLang == 'fr'
      ? 'Guide_demarrage_rapide_BZ_light.pdf'
      : 'Quick_Guide_BZL.pdf';
  }

  List<Map<String, dynamic>> get _docs => [
    {'title': _lang.t('bzLightTechSheet'), 'file': 'Fiche_technique_BZ_Light.pdf',    'icon': Icons.description_outlined, 'color': 0xFFEF4444},
    {'title': _lang.t('quickStartGuide'),  'file': _quickGuideFile(),                 'icon': Icons.play_lesson_outlined,  'color': 0xFF22D3EE},
    {'title': _lang.t('userManual'),       'file': 'Manuel_utilisation_BZ_light.pdf', 'icon': Icons.menu_book_outlined,    'color': 0xFFA855F7},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionTitle(_lang.t('documentation'), Icons.folder_outlined),
      const SizedBox(height: 12),
      ..._docs.map((doc) =>
        GestureDetector(
          onTap: () => _openPdfFile(context, doc['file'] as String, doc['title'] as String),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: BzColors.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BzColors.border)),
            child: Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Color(doc['color'] as int).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(doc['icon'] as IconData,
                  color: Color(doc['color'] as int), size: 20)),
              const SizedBox(width: 14),
              Expanded(child: Text(doc['title'] as String,
                style: const TextStyle(color: BzColors.textMain,
                  fontWeight: FontWeight.w600, fontSize: 13))),
              Icon(Icons.open_in_new, color: BzColors.textHint, size: 16),
            ]),
          ),
        )
      ),
      const SizedBox(height: 24),
      _sectionTitle(_lang.t('contact'), Icons.contact_phone_outlined),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: BzColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BzColors.red.withOpacity(0.25))),
        child: _loadingReseller
          ? const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: BzColors.red))))
          : Row(children: [
              Container(width: 46, height: 46,
                decoration: const BoxDecoration(
                  color: BzColors.redTint,
                  shape: BoxShape.circle),
                child: const Icon(Icons.support_agent,
                  color: BzColors.red, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _reseller.isNotEmpty ? _reseller : _lang.t('resellerUnknown'),
                  style: const TextStyle(color: BzColors.textMain,
                    fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 2),
                Text(_lang.t('contactResellerDesc'),
                  style: const TextStyle(color: BzColors.textHint, fontSize: 11, height: 1.4)),
              ])),
            ]),
      ),
      const SizedBox(height: 20),
    ]);
  }

  Future<void> _openPdfFile(BuildContext context, String file, String title) async {
    try {
      final byteData = await rootBundle.load('assets/$file');
      final tempDir  = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$file');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewerScreen(path: tempFile.path, title: title)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_lang.t('pdfOpenError')} : $e'),
          backgroundColor: Colors.red[900],
          behavior: SnackBarBehavior.floating));
      }
    }
  }
}

// ══════════════════════════════════════════════════
// ONGLET 4 — DIAGNOSTIC
// ══════════════════════════════════════════════════
class _DiagnosticTab extends StatefulWidget {
  @override
  State<_DiagnosticTab> createState() => _DiagnosticTabState();
}

class _DiagnosticTabState extends State<_DiagnosticTab> {
  // Arbre de décision
  String _currentNode = 'root';
  final List<String> _history = [];

  // Arbre de décision — les textes sont des clés de traduction
  Map<String, Map<String, dynamic>> _buildTree(LangService l) => {
    'root': {
      'type': 'question',
      'text': l.t('diagTitle'),
      'options': [
        {'label': l.t('diagIssueLift'),    'next': 'lift_1'},
        {'label': l.t('diagIssueCam'),     'next': 'cam_1'},
        {'label': l.t('diagIssueTorsion'), 'next': 'torsion_1'},
      ],
    },

    // ── Bras qui ne lève plus ──
    'lift_1': {
      'type': 'question',
      'text': l.t('diagLiftQ1'),
      'options': [
        {'label': l.t('diagOk'), 'next': 'lift_2'},
      ],
    },
    'lift_2': {
      'type': 'question',
      'text': l.t('diagLiftQ2'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'lift_fuite'},
        {'label': l.t('diagNo'),  'next': 'lift_tiges_q'},
      ],
    },
    'lift_fuite': {
      'type': 'question',
      'text': l.t('diagLiftQ3'),
      'options': [
        {'label': l.t('diagLiftOptPurge'),   'next': 'lift_sol_purge'},
        {'label': l.t('diagLiftOptArriere'), 'next': 'lift_sol_arriere'},
        {'label': l.t('diagLiftOptAutre'),   'next': 'lift_sol_autre'},
      ],
    },
    'lift_sol_purge': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagLiftSol1'),
    },
    'lift_sol_arriere': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagLiftSol2'),
    },
    'lift_sol_autre': {
      'type': 'solution',
      'text': l.t('diagContactSupport'),
      'detail': l.t('diagLiftSol3'),
    },
    'lift_tiges_q': {
      'type': 'question',
      'text': l.t('diagLiftQ4'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'lift_piston_q'},
        {'label': l.t('diagNo'),  'next': 'lift_sol_tiges'},
      ],
    },
    'lift_sol_tiges': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagLiftSol5'),
    },
    'lift_piston_q': {
      'type': 'question',
      'text': l.t('diagLiftQ5'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'lift_sol_inconnu'},
        {'label': l.t('diagNo'),  'next': 'lift_sol_piston'},
      ],
    },
    'lift_sol_piston': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagLiftSol4'),
    },
    'lift_sol_inconnu': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagLiftSol6'),
    },

    // ── Caméra ne fonctionne plus ──
    'cam_1': {
      'type': 'question',
      'text': l.t('diagCamQ1'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'cam_2'},
        {'label': l.t('diagNo'),  'next': 'cam_sol_quality'},
      ],
    },
    'cam_sol_quality': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagCamSol1'),
    },
    'cam_2': {
      'type': 'question',
      'text': l.t('diagCamQ2'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'cam_sol_module'},
        {'label': l.t('diagNo'),  'next': 'cam_sol_arriere'},
      ],
    },
    'cam_sol_module': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagCamSol3'),
    },
    'cam_sol_arriere': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagCamSol2'),
    },

    // ── Câble de torsion tourne difficilement ou reste bloqué ──
    'torsion_1': {
      'type': 'question',
      'text': l.t('diagTorsionQ1'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'torsion_sol_cable'},
        {'label': l.t('diagNo'),  'next': 'torsion_2'},
      ],
    },
    'torsion_sol_cable': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagTorsionSol1'),
    },
    'torsion_2': {
      'type': 'question',
      'text': l.t('diagTorsionQ2'),
      'options': [
        {'label': l.t('diagYes'), 'next': 'torsion_info'},
        {'label': l.t('diagNo'),  'next': 'torsion_sol_graisse'},
      ],
    },
    'torsion_sol_graisse': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagTorsionSol2'),
    },
    'torsion_info': {
      'type': 'question',
      'text': l.t('diagTorsionInfo'),
      'options': [
        {'label': l.t('diagOk'), 'next': 'torsion_3'},
      ],
    },
    'torsion_3': {
      'type': 'question',
      'text': l.t('diagTorsionQ3'),
      'options': [
        {'label': l.t('diagTorsionOptRoulement'), 'next': 'torsion_sol_roulement'},
        {'label': l.t('diagTorsionOptEngrenage'),  'next': 'torsion_sol_engrenage'},
        {'label': l.t('diagTorsionOptAutre'),      'next': 'torsion_sol_inconnu'},
      ],
    },
    'torsion_sol_roulement': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagTorsionSol3'),
    },
    'torsion_sol_engrenage': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagTorsionSol4'),
    },
    'torsion_sol_inconnu': {
      'type': 'solution',
      'text': l.t('diagSolution'),
      'detail': l.t('diagTorsionSol5'),
    },
  };

  void _navigate(String nodeId) {
    setState(() {
      _history.add(_currentNode);
      _currentNode = nodeId;
    });
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      setState(() {
        _currentNode = _history.removeLast();
      });
    }
  }

  void _reset() {
    setState(() {
      _currentNode = 'root';
      _history.clear();
    });
  }

  void _showFlowControlImage(BuildContext context) {
    final l = LangService();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BzColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Image.asset('assets/images/Air_flow_control.png',
              width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 200, color: BzColors.surface,
                child: const Center(child: Icon(Icons.image_not_supported,
                  color: BzColors.textHint, size: 48)))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(l.t('diagFlowHandleCaption'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.t('close'),
                    style: const TextStyle(color: BzColors.red,
                      fontWeight: FontWeight.w700))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showLeakLocationImage(BuildContext context) {
    final l = LangService();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BzColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              Text(l.t('diagLeakLocationCaption'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
              const SizedBox(height: 16),

              // ── Image 1 : Purge ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.t('diagLeakOptPurgeLabel'),
                  style: const TextStyle(color: BzColors.red,
                    fontWeight: FontWeight.w800, fontSize: 13))),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Image.asset('assets/Purge.png',
                    width: double.infinity, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 160, color: BzColors.surface,
                      child: const Center(child: Icon(Icons.image_not_supported,
                        color: BzColors.textHint, size: 40)))),
                ),
              ),
              const SizedBox(height: 20),

              // ── Image 2 : Module arrière ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.t('diagLeakOptArriereLabel'),
                  style: const TextStyle(color: BzColors.red,
                    fontWeight: FontWeight.w800, fontSize: 13))),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Image.asset('assets/module_arriere.png',
                    width: double.infinity, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 160, color: BzColors.surface,
                      child: const Center(child: Icon(Icons.image_not_supported,
                        color: BzColors.textHint, size: 40)))),
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.t('close'),
                      style: const TextStyle(color: BzColors.red,
                        fontWeight: FontWeight.w700))),
                ),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  void _showTigesImage(BuildContext context) {
    final l = LangService();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BzColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Image.asset('assets/images/tiges.png',
              width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 200, color: BzColors.surface,
                child: const Center(child: Icon(Icons.image_not_supported,
                  color: BzColors.textHint, size: 48)))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(l.t('diagTigesCaption'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.t('close'),
                    style: const TextStyle(color: BzColors.red,
                      fontWeight: FontWeight.w700))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
  void _showGreasedImage(BuildContext context) {
    final l = LangService();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BzColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Image.asset('assets/images/greased.jpg',
              width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 200, color: BzColors.surface,
                child: const Center(child: Icon(Icons.image_not_supported,
                  color: BzColors.textHint, size: 48)))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(l.t('diagCamConnectorCaption'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.t('close'),
                    style: const TextStyle(color: BzColors.red,
                      fontWeight: FontWeight.w700))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildQuestionText(BuildContext context, String nodeId, String text) {
    // Détermine le mot cliquable et l'action selon le nœud
    String? clickable;
    VoidCallback? onTap;

    if (nodeId == 'lift_1' || nodeId == 'lift_tiges_q') {
      clickable = LangService().t('diagLiftRods');
      onTap = () => _showTigesImage(context);
    }

    if (clickable == null || onTap == null) {
      return Text(text, style: const TextStyle(color: BzColors.textMain,
        fontWeight: FontWeight.w900, fontSize: 15));
    }

    // Recherche du mot cliquable
    int idx = text.indexOf(clickable);
    if (idx == -1) idx = text.toLowerCase().indexOf(clickable.toLowerCase());

    if (idx == -1) {
      // Fallback : texte entier cliquable
      return GestureDetector(
        onTap: onTap,
        child: Text(text, style: const TextStyle(
          color: BzColors.red,
          fontWeight: FontWeight.w900,
          fontSize: 15,
          decoration: TextDecoration.underline,
          decorationColor: BzColors.red)),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: BzColors.textMain,
          fontWeight: FontWeight.w900, fontSize: 15),
        children: [
          TextSpan(text: text.substring(0, idx)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                text.substring(idx, idx + clickable.length),
                style: const TextStyle(
                  color: BzColors.red,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                  decorationColor: BzColors.red),
              ),
            ),
          ),
          TextSpan(text: text.substring(idx + clickable.length)),
        ],
      ),
    );
  }

  Future<void> _openPdfFile(BuildContext context, String file, String title) async {
    try {
      final byteData = await rootBundle.load('assets/$file');
      final tempDir  = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$file');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewerScreen(path: tempFile.path, title: title)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur PDF : $e'),
          backgroundColor: Colors.red[900],
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  // Mapping nœud solution → ID vidéo YouTube
  String? _nodeVideoId(String nodeId) {
    switch (nodeId) {
      case 'lift_sol_tiges':    return 'KrNA8CR_x9E'; // Vidéo Nettoyage
      case 'cam_sol_module':    return 'fwQJbY4NCog'; // Camera module replacement
      case 'lift_sol_piston':   return 'LxCpT7f6qR8'; // Clean and grease the piston
      case 'lift_sol_arriere':  return 'nrQGiUvbrcY'; // Rear module replacement
      case 'cam_sol_arriere':   return 'nrQGiUvbrcY'; // Rear module replacement
      case 'torsion_sol_cable': return 'LTiIcKyBDu8'; // Replace the rear casing
      default: return null;
    }
  }

  // Mapping nœud solution → PDF
  Map<String, String>? _nodePdf(String nodeId) {
    switch (nodeId) {
      case 'cam_sol_module': return {
        'file': 'Camera_module_replacement.pdf',
        'title': 'Camera module replacement',
      };
      case 'lift_sol_arriere': return {
        'file': 'Changement_module_arriere.pdf',
        'title': 'Rear module replacement',
      };
      case 'cam_sol_arriere': return {
        'file': 'Changement_module_arriere.pdf',
        'title': 'Rear module replacement',
      };
      default: return null;
    }
  }

  // Mapping nœud → action image
  VoidCallback? _nodeImageAction(BuildContext context, String nodeId) {
    switch (nodeId) {
      case 'lift_tiges_q':  return () => _showTigesImage(context);
      case 'lift_fuite':    return () => _showLeakLocationImage(context);
      case 'cam_2':    return () => _showGreasedImage(context);
      default:         return null;
    }
  }

  Widget _buildNodeIcon(BuildContext context, String nodeId,
      bool isSolution, bool isContact) {
    if (isSolution) {
      return Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isContact
            ? const Color(0xFFA855F7).withOpacity(0.15)
            : const Color(0xFF22D3EE).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(
          isContact ? Icons.phone_in_talk : Icons.check_circle_outline,
          color: isContact ? const Color(0xFFA855F7) : const Color(0xFF22D3EE),
          size: 20));
    }

    final action = _nodeImageAction(context, nodeId);
    if (action == null) return const SizedBox(width: 40, height: 40);

    return GestureDetector(
      onTap: action,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: BzColors.redTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BzColors.red.withOpacity(0.3))),
        child: const Icon(Icons.help_outline,
          color: BzColors.red, size: 20)),
    );
  }

  Widget _buildSolutionDetail(BuildContext context, String nodeId, String text) {
    return Text(text, style: const TextStyle(color: BzColors.textMuted,
      fontSize: 13, height: 1.7));
  }

  @override
  Widget build(BuildContext context) {
    final l    = LangService();
    final tree = _buildTree(l);
    final node = tree[_currentNode]!;
    final isSolution = node['type'] == 'solution';
    final isContact  = isSolution && (node['text'] as String).contains(l.t('diagContactSupport'));

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Fil d'Ariane
      if (_history.isNotEmpty)
        Row(children: [
          GestureDetector(
            onTap: _goBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BzColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BzColors.border)),
              child: Row(children: [
                const Icon(Icons.arrow_back, color: BzColors.textMuted, size: 14),
                const SizedBox(width: 4),
                Text(l.t('diagBack'), style: const TextStyle(color: BzColors.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _reset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BzColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BzColors.border)),
              child: Row(children: [
                const Icon(Icons.refresh, color: BzColors.textMuted, size: 14),
                const SizedBox(width: 4),
                Text(l.t('diagRestart'), style: const TextStyle(color: BzColors.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),

      if (_history.isNotEmpty) const SizedBox(height: 16),

      // Carte principale
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSolution
            ? (isContact
                ? const Color(0xFFF5EEFC)
                : const Color(0xFFE9FAFB))
            : BzColors.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSolution
              ? (isContact
                  ? const Color(0xFFA855F7).withOpacity(0.4)
                  : const Color(0xFF22D3EE).withOpacity(0.4))
              : BzColors.border),
          boxShadow: isSolution ? [BoxShadow(
            color: (isContact
              ? const Color(0xFFA855F7)
              : const Color(0xFF22D3EE)).withOpacity(0.1),
            blurRadius: 20)] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _buildNodeIcon(context, _currentNode, isSolution, isContact),
            const SizedBox(width: 12),
            Expanded(child: isSolution
              ? Text(node['text'] as String,
                  style: TextStyle(
                    color: isContact ? const Color(0xFF7C3AED) : const Color(0xFF0E7490),
                    fontWeight: FontWeight.w900, fontSize: 15))
              : Text(node['text'] as String,
                  style: const TextStyle(color: BzColors.textMain,
                    fontWeight: FontWeight.w900, fontSize: 15))),
          ]),

          if (isSolution) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10)),
              child: _buildSolutionDetail(context, _currentNode, node['detail'] as String)),
            // Bouton vidéo si disponible
            if (_nodeVideoId(_currentNode) != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _VideoPlayerScreen(
                    title: node['detail'] as String,
                    videoId: _nodeVideoId(_currentNode)!))),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: BzColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: BzColors.red.withOpacity(0.4))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.play_circle_outline, color: BzColors.red, size: 20),
                    SizedBox(width: 8),
                    Text('▶ Voir la vidéo', style: TextStyle(
                      color: BzColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
            ],
            // Bouton PDF si disponible
            if (_nodePdf(_currentNode) != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _openPdfFile(
                  context,
                  _nodePdf(_currentNode)!['file']!,
                  _nodePdf(_currentNode)!['title']!),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.4))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.picture_as_pdf_outlined, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('📄 Voir la notice', style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
            ],
            // Image illustrative pour le réglage du mode vidéo CVBS
            if (_currentNode == 'cam_sol_quality') ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/modeCVBS.png',
                  width: double.infinity, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160, color: BzColors.surface,
                    child: const Center(child: Icon(Icons.image_not_supported,
                      color: BzColors.textHint, size: 40)))),
              ),
            ],
            const SizedBox(height: 16),
            _SatisfactionForm(
              nodeId: _currentNode,
              onSubmitted: _reset,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l.t('diagNewDiag'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BzColors.textMuted,
                  side: const BorderSide(color: BzColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ]),
      ),

      // Options de réponse
      if (!isSolution) ...[
        const SizedBox(height: 16),
        ...(node['options'] as List).map((opt) =>
          GestureDetector(
            onTap: () => _navigate(opt['next'] as String),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BzColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BzColors.border)),
              child: Row(children: [
                Expanded(child: Text(opt['label'] as String,
                  style: const TextStyle(color: BzColors.textMain,
                    fontSize: 13, fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right, color: BzColors.textHint, size: 18),
              ]),
            ),
          )
        ),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════
// FORMULAIRE DE SATISFACTION
// ══════════════════════════════════════════════════
class _SatisfactionForm extends StatefulWidget {
  final String nodeId;
  final VoidCallback onSubmitted;
  const _SatisfactionForm({required this.nodeId, required this.onSubmitted});
  @override
  State<_SatisfactionForm> createState() => _SatisfactionFormState();
}

class _SatisfactionFormState extends State<_SatisfactionForm> {
  static const String _feedbackEmail = 'feedback@bzbots.com'; // ← à changer
  final _lang        = LangService();
  bool? _effective;
  final _reasonCtrl  = TextEditingController();
  bool _submitted    = false;
  bool _sending      = false;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    setState(() => _sending = true);
    final subject = Uri.encodeComponent(
      '[BzLight Diagnostic] Satisfaction — ${widget.nodeId}');
    final body = Uri.encodeComponent(
      'Nœud de diagnostic : ${widget.nodeId}\n'
      'Diagnostic efficace : ${_effective == true ? "Oui" : "Non"}\n'
      '${_effective == false && _reasonCtrl.text.isNotEmpty ? "Raison : ${_reasonCtrl.text}" : ""}');
    final uri = Uri.parse('mailto:$_feedbackEmail?subject=$subject&body=$body');
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {}
    setState(() { _submitted = true; _sending = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.3))),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
          const SizedBox(width: 10),
          Text(_lang.t('diagFeedbackThanks'),
            style: const TextStyle(color: Colors.green,
              fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BzColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BzColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_lang.t('diagFeedbackQuestion'),
          style: const TextStyle(color: BzColors.textMain,
            fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _effective = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _effective == true
                  ? Colors.green.withOpacity(0.12)
                  : BzColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _effective == true
                    ? Colors.green.withOpacity(0.5)
                    : BzColors.border)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.thumb_up_outlined,
                  color: _effective == true ? Colors.green : BzColors.textHint,
                  size: 16),
                const SizedBox(width: 6),
                Text(_lang.t('diagFeedbackYes'),
                  style: TextStyle(
                    color: _effective == true ? Colors.green : BzColors.textMuted,
                    fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _effective = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _effective == false
                  ? BzColors.red.withOpacity(0.1)
                  : BzColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _effective == false
                    ? BzColors.red.withOpacity(0.4)
                    : BzColors.border)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.thumb_down_outlined,
                  color: _effective == false ? BzColors.red : BzColors.textHint,
                  size: 16),
                const SizedBox(width: 6),
                Text(_lang.t('diagFeedbackNo'),
                  style: TextStyle(
                    color: _effective == false ? BzColors.red : BzColors.textMuted,
                    fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          )),
        ]),

        // Champ texte si non efficace
        if (_effective == false) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            style: const TextStyle(color: BzColors.textMain, fontSize: 13),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: _lang.t('diagFeedbackReasonHint'),
              hintStyle: const TextStyle(color: BzColors.textHint, fontSize: 12),
              filled: true,
              fillColor: BzColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: BzColors.border)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: BzColors.border)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: BzColors.red))),
          ),
        ],

        if (_effective != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: BzColors.solidFill,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0),
              child: _sending
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : Text(_lang.t('diagFeedbackSend'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════
// HELPERS PARTAGÉS
// ══════════════════════════════════════════════════
Widget _sectionTitle(String title, IconData icon) {
  return Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: BzColors.redTint,
        borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, color: BzColors.red, size: 15)),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(color: BzColors.red, fontSize: 10,
      fontWeight: FontWeight.w900, letterSpacing: 2)),
  ]);
}

// ── Lecteur YouTube ──────────────────────────────
// ══════════════════════════════════════════════════
// CHAPITRES VIDÉO — bouton "aller à" un instant précis
// ══════════════════════════════════════════════════
// Clé = videoId YouTube, valeur = liste de chapitres
// {'label': nom affiché, 'seconds': position en secondes}
// À compléter au fur et à mesure (laisser [] si aucun chapitre pour l'instant)
const Map<String, List<Map<String, Object>>> _videoChapters = {
  'KrNA8CR_x9E': [], // Nettoyage
  'eARLGuMHqLU': [], // Nettoyage approfondi
  'fwQJbY4NCog': [ // Camera module replacement
    {'label': 'chapCamRemoveModule',   'seconds': 0},
    {'label': 'chapCamChangeModule',   'seconds': 34},
    {'label': 'chapCamReassemble',     'seconds': 54},
  ],
  'LxCpT7f6qR8': [ // Clean and grease the piston
    {'label': 'chapPistonDisassembleRobot',  'seconds': 0},
    {'label': 'chapPistonDisassemble',       'seconds': 71},
    {'label': 'chapPistonCleanReassemble',   'seconds': 137},
    {'label': 'chapPistonReassembleRobot',   'seconds': 290},
  ],
  'nrQGiUvbrcY': [ // Rear module replacement
    {'label': 'chapRearDisassembleRobot', 'seconds': 0},
    {'label': 'chapRearChangeModule',     'seconds': 60},
    {'label': 'chapRearReassembleRobot',  'seconds': 65},
  ],
  'LTiIcKyBDu8': [], // Replace the rear casing
};

class _VideoPlayerScreen extends StatefulWidget {
  final String title, videoId;
  const _VideoPlayerScreen({required this.title, required this.videoId});
  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  int? _activeChapterIndex;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(autoPlay: true, mute: false));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _jumpTo(int index, int seconds) {
    _controller.seekTo(Duration(seconds: seconds));
    setState(() => _activeChapterIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _videoChapters[widget.videoId] ?? [];
    return YoutubePlayerBuilder(
      player: YoutubePlayer(controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: BzColors.red),
      builder: (context, player) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
          title: Text(widget.title, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
        body: Column(children: [
          player,
          if (chapters.isNotEmpty) ...[
            const SizedBox(height: 4),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: chapters.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final chapter  = chapters[i];
                  final isActive = _activeChapterIndex == i;
                  final seconds  = chapter['seconds'] as int;
                  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
                  final ss = (seconds % 60).toString().padLeft(2, '0');
                  return GestureDetector(
                    onTap: () => _jumpTo(i, seconds),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive
                          ? BzColors.red.withOpacity(0.12)
                          : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                            ? BzColors.red.withOpacity(0.5)
                            : Colors.white.withOpacity(0.08))),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? BzColors.red : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text('$mm:$ss', style: TextStyle(
                            color: isActive ? Colors.white : Colors.white70,
                            fontSize: 11, fontWeight: FontWeight.w800,
                            fontFamily: 'monospace'))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(LangService().t(chapter['label'] as String),
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600))),
                        Icon(Icons.play_circle_outline,
                          color: isActive ? BzColors.red : Colors.white38, size: 18),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ])));
  }
}

// ── Lecteur PDF ──────────────────────────────────
class _PdfViewerScreen extends StatefulWidget {
  final String path;
  final String title;
  const _PdfViewerScreen({required this.path, required this.title});
  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
  int _totalPages  = 0;
  int _currentPage = 0;
  bool _isReady    = false;
  PDFViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BzColors.bg,
      appBar: AppBar(
        backgroundColor: BzColors.solidFill,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13)),
        actions: [
          if (_isReady)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('$_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)))),
        ],
      ),
      body: Stack(children: [
        PDFView(
          filePath: widget.path,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          backgroundColor: BzColors.bg,
          onRender: (pages) => setState(() {
            _totalPages = pages ?? 0;
            _isReady    = true;
          }),
          onViewCreated: (ctrl) => setState(() => _controller = ctrl),
          onPageChanged: (page, _) => setState(() => _currentPage = (page ?? 0) + 1),
          onError: (e) => Center(child: Text('Erreur : $e',
            style: const TextStyle(color: Colors.red))),
        ),
        if (!_isReady)
          const Center(child: CircularProgressIndicator(color: BzColors.red)),
      ]),
      // Navigation bas de page
      bottomNavigationBar: _isReady && _totalPages > 1
        ? SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: BzColors.bg,
                border: Border(top: BorderSide(color: BzColors.border))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(
                  onPressed: _currentPage > 1
                    ? () => _controller?.setPage(_currentPage - 2)
                    : null,
                  icon: Icon(Icons.chevron_left,
                    color: _currentPage > 1 ? BzColors.textMain : BzColors.border, size: 28)),
                Text('Page $_currentPage sur $_totalPages',
                  style: const TextStyle(color: BzColors.textMuted, fontSize: 12)),
                IconButton(
                  onPressed: _currentPage < _totalPages
                    ? () => _controller?.setPage(_currentPage)
                    : null,
                  icon: Icon(Icons.chevron_right,
                    color: _currentPage < _totalPages ? BzColors.textMain : BzColors.border,
                    size: 28)),
              ]),
            ))
        : null,
    );
  }
}

// ══════════════════════════════════════════════════
// ONGLET CAS D'EMPLOI
// ══════════════════════════════════════════════════
class _CasEmploiTab extends StatefulWidget {
  const _CasEmploiTab();
  @override
  State<_CasEmploiTab> createState() => _CasEmploiTabState();
}

class _CasEmploiTabState extends State<_CasEmploiTab> {

  // Matrice CAS x DN
  final _lang = LangService();
  final _auth = AuthService();
  final _cart = CartService();

  static const _dns = [
    {'label': 'DN100', 'adapter': 'BZL-AC-011'},
    {'label': 'DN125', 'adapter': 'BZL-AC-040'},
    {'label': 'DN160', 'adapter': 'BZL-AC-020'},
    {'label': 'DN200', 'adapter': 'BZL-AC-030 + 12xBZL-AC-032-B'},
    {'label': 'DN250', 'adapter': 'BZL-AC-030 + 12xBZL-AC-032-B'},
  ];

  // Clés internes fixes (ne changent pas selon la langue)
  static const _casKeys = [
    'casEmploiRéouverture',
    'casEmploiFerBeton',
    'casEmploiBeton',
    'casEmploiGaine',
  ];

  // Matrice : CAS → DN → {outil, sortie}
  static const _matrix = {
    'casEmploiRéouverture': {
      'DN100': {'outil': 'OCO-CL-45/18-38F', 'sortie': 'BZL-011'},
      'DN125': {'outil': 'OCO-CL-45/18-38F', 'sortie': 'BZL-011'},
      'DN160': {'outil': 'OCO-CL-45/18-38F', 'sortie': 'BZL-011-B'},
      'DN200': {'outil': 'OCO-CL-45/18-38F', 'sortie': 'BZL-011-B'},
      'DN250': {'outil': 'OCO-CL-45/18-38F', 'sortie': 'BZL-011-B + BZL-A-106'},
    },
    'casEmploiFerBeton': {
      'DN100': {'outil': 'OCD-65-2-D', 'sortie': 'BZL-ASD-010 + BZL-ASD-107'},
      'DN125': {'outil': 'OCD-65-2-D', 'sortie': 'BZL-ASD-010 + BZL-ASD-107'},
      'DN160': {'outil': 'OCD-75-2-D', 'sortie': 'BZL-ASD-010 + BZL-ASD-110'},
      'DN200': {'outil': 'OCD-75-2-D', 'sortie': 'BZL-011 + BZL-A-107 + BZL-ASD-109'},
      'DN250': {'outil': 'OCD-75-2-D', 'sortie': 'BZL-011-B + BZL-A-107 + BZL-A-108 + BZL-ASD-109'},
    },
    'casEmploiBeton': {
      'DN100': {'outil': 'OCB-BO-46-12-38', 'sortie': 'BZL-011'},
      'DN125': {'outil': 'OCB-BO-46-12-38', 'sortie': 'BZL-011'},
      'DN160': {'outil': 'OCB-BO-46-12-38', 'sortie': 'BZL-011-B'},
      'DN200': {'outil': 'OCB-BO-46-12-38', 'sortie': 'BZL-011-B'},
      'DN250': {'outil': 'OCB-BO-46-12-38', 'sortie': 'BZL-011-B + BZL-A-106'},
    },
    'casEmploiGaine': {
      'DN100': {'outil': 'casEmploiEnCours', 'sortie': ''},
      'DN125': {'outil': 'casEmploiEnCours', 'sortie': ''},
      'DN160': {'outil': 'casEmploiEnCours', 'sortie': ''},
      'DN200': {'outil': 'casEmploiEnCours', 'sortie': ''},
      'DN250': {'outil': 'casEmploiEnCours', 'sortie': ''},
    },
  };

  // Mapping CAS+DN → image côté
  static const _images = {
    'casEmploiFerBeton|DN100': ['assets/DN100_65_cote.png'],
    'casEmploiFerBeton|DN125': ['assets/DN125_65_cote.png'],
    'casEmploiFerBeton|DN160': ['assets/DN160_75_cote.png'],
    'casEmploiFerBeton|DN200': ['assets/DN200_75_cote.png'],
    'casEmploiFerBeton|DN250': ['assets/DN250_75_cote.png'],
  };

  // Mapping outil → image
  static const _outilImages = {
    'OCO-CL-45/18-38F': 'assets/cloche.png',
    'OCB-BO-46-12-38':  'assets/Boule_beton.png',
    'OCD-75-2-D':       'assets/OCD-75-2-D.png',
    'OCD-65-2-D':       'assets/OCD-65-2-D.png',
  };

  static const _centreurImages = {
    'BZL-AC-011':   'assets/BZL_AC_011.png',
    'BZL-AC-030':   'assets/BZL-AC-030.png',
    'BZL-AC-032-A': 'assets/BZL-AC-032-A.png',
    'BZL-AC-032-B': 'assets/BZL-AC-032-B.png',
  };

  static const _accessoireImages = {
    'BZL-011':     'assets/BZL-011.png',
    'BZL-011-B':   'assets/BZL-011-B.png',
    'BZL-A-107':   'assets/BZL-A-107.png',
    'BZL-A-108':   'assets/BZL-A-108.png',
    'BZL-ASD-010': 'assets/BZL-ASD-010.png',
    'BZL-ASD-109': 'assets/BZL-ASD-109.png',
  };

  String? _selectedCasKey;
  String? _selectedDn;

  String? get _adapter {
    if (_selectedDn == null) return null;
    return _dns.firstWhere((d) => d['label'] == _selectedDn)['adapter'];
  }

  Map<String, String>? get _result {
    if (_selectedCasKey == null || _selectedDn == null) return null;
    return _matrix[_selectedCasKey!]?[_selectedDn!];
  }

  bool get _isEnCours => _result?['outil'] == 'casEmploiEnCours';

  List<String>? get _resultImages {
    if (_selectedCasKey == null || _selectedDn == null) return null;
    return _images['$_selectedCasKey|$_selectedDn'];
  }

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _addToCart(String id) async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    final img = _centreurImages[id]
             ?? _outilImages[id]
             ?? _accessoireImages[id]
             ?? '';
    await _cart.addItem(user.$id, CartItem(
      id:          id,
      name:        id,
      version:     '',
      robotSerial: '',
      img:         img,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.shopping_cart, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('$id ${_lang.t('cartAdded')}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: BzColors.solidFill,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  String? _imageFor(String id) =>
      _centreurImages[id] ?? _outilImages[id] ?? _accessoireImages[id];

  // Couleur + libellé associés à chaque catégorie de pièce
  Map<String, Object> _categoryStyle(String? category) {
    switch (category) {
      case 'centreur':
        return {'color': const Color(0xFF3B82F6), 'label': _lang.t('casEmploiAdaptateur')};
      case 'outil':
        return {'color': BzColors.red, 'label': _lang.t('casEmploiOutil')};
      case 'accessoire':
        return {'color': const Color(0xFF9333EA), 'label': _lang.t('casEmploiAccessoires')};
      default:
        return {'color': BzColors.textHint, 'label': ''};
    }
  }

  Widget _productCard(String id, {String? displayLabel, String? category}) {
    final img = _imageFor(id);
    final catStyle = _categoryStyle(category);
    final catColor = catStyle['color'] as Color;
    final catLabel = catStyle['label'] as String;
    return Container(
      decoration: BoxDecoration(
        color: BzColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BzColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Badge catégorie coloré — bandeau au-dessus de l'image
        if (catLabel.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: catColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
            child: Center(
              child: Text(catLabel.toUpperCase(),
                style: const TextStyle(color: Colors.white,
                  fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            ),
          ),
        // Image produit (cliquable pour zoom si disponible)
        AspectRatio(
          aspectRatio: 1.2,
          child: GestureDetector(
            onTap: img == null ? null : () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  minScale: 0.5, maxScale: 6.0,
                  child: Image.asset(img, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported, color: Colors.white24, size: 40))))),
            child: ClipRRect(
              borderRadius: catLabel.isNotEmpty
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(14)),
              child: Container(
                color: BzColors.surface,
                child: img == null
                  ? const Center(child: Icon(Icons.inventory_2_outlined,
                      color: BzColors.textHint, size: 32))
                  : Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(img, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_not_supported,
                            color: BzColors.textHint, size: 32)))),
              ),
            ),
          ),
        ),
        // Nom + bouton ajouter
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayLabel ?? id,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BzColors.textMain,
                fontSize: 12.5, fontWeight: FontWeight.w800,
                fontFamily: 'monospace', height: 1.25)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _addToCart(id),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: BzColors.redTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BzColors.red.withOpacity(0.4))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_shopping_cart, color: BzColors.red, size: 13),
                  const SizedBox(width: 5),
                  Text(_lang.t('cartAdd'), style: const TextStyle(
                    color: BzColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Text(_lang.t('casEmploi'), style: const TextStyle(
          color: BzColors.textMain, fontWeight: FontWeight.w900,
          fontSize: 18, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(_lang.t('casEmploiSubtitle'),
          style: const TextStyle(color: BzColors.textHint, fontSize: 12)),
        const SizedBox(height: 24),

        // Dropdown CAS
        _buildDropdownLabel(_lang.t('casEmploiCas')),
        const SizedBox(height: 8),
        _buildDropdown(
          value: _selectedCasKey,
          items: _casKeys,
          displayText: (key) => _lang.t(key),
          hint: _lang.t('casEmploiSelectCas'),
          onChanged: (v) => setState(() { _selectedCasKey = v; }),
        ),
        const SizedBox(height: 16),

        // Dropdown DN
        _buildDropdownLabel(_lang.t('casEmploiDn')),
        const SizedBox(height: 8),
        _buildDropdown(
          value: _selectedDn,
          items: _dns.map((d) => d['label']!).toList(),
          displayText: (v) => v,
          hint: _lang.t('casEmploiSelectDn'),
          onChanged: (v) => setState(() { _selectedDn = v; }),
        ),
        const SizedBox(height: 32),

        if (_result != null) _buildResult(),
      ]),
    );
  }

  Widget _buildDropdownLabel(String label) {
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: BzColors.red, width: 3))),
      child: Text(label, style: const TextStyle(
        color: BzColors.textMuted, fontSize: 11,
        fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required String Function(String) displayText,
    required String hint,
    required void Function(String?) onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: BzColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BzColors.red.withOpacity(0.3))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: const TextStyle(color: BzColors.textHint, fontSize: 13)),
          dropdownColor: BzColors.bg,
          iconEnabledColor: BzColors.red,
          isExpanded: true,
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(displayText(item), style: const TextStyle(
              color: BzColors.textMain, fontSize: 13, fontWeight: FontWeight.w600)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildResult() {
    final outil  = _result!['outil']!;
    final sortie = _result!['sortie']!;
    final isEnCours = _isEnCours;

    // Construction de la liste unique des références à afficher en grille
    final List<Map<String, String>> items = [];
    if (!isEnCours) {
      for (final part in (_adapter ?? '').split(' + ')) {
        final raw = part.trim();
        if (raw.isEmpty) continue;
        final imgKey = RegExp(r'^\d+\s*x\s*(.+)$', caseSensitive: false).firstMatch(raw)?.group(1) ?? raw;
        items.add({'id': imgKey, 'label': raw, 'category': 'centreur'});
      }
      items.add({'id': outil, 'label': outil, 'category': 'outil'});
      if (sortie.isNotEmpty) {
        for (final part in sortie.split(' + ')) {
          final raw = part.trim();
          if (raw.isEmpty) continue;
          items.add({'id': raw, 'label': raw, 'category': 'accessoire'});
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BzColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnCours
            ? BzColors.border
            : BzColors.red.withOpacity(0.5)),
        boxShadow: [BoxShadow(
          color: isEnCours
            ? Colors.transparent
            : BzColors.red.withOpacity(0.08),
          blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Images en haut si disponibles
        if (_resultImages != null) ...[
          Row(children: [
            const Icon(Icons.image_outlined, color: BzColors.textHint, size: 14),
            const SizedBox(width: 6),
            Text(_lang.t('casEmploiVues'), style: const TextStyle(
              color: BzColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  minScale: 0.5, maxScale: 6.0,
                  child: Image.asset(_resultImages![0], fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported, color: Colors.white24, size: 40))))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(_resultImages![0],
                width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 160, color: BzColors.surface,
                  child: const Icon(Icons.image_not_supported,
                    color: BzColors.textHint, size: 30))))),
          const SizedBox(height: 16),
          const Divider(color: BzColors.border),
          const SizedBox(height: 16),
        ],
        if (isEnCours) ...[
          Text(_lang.t('casEmploiEnCours'), style: const TextStyle(
            color: BzColors.textMuted, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(_lang.t('casEmploiEnCoursMsg'),
            style: const TextStyle(color: BzColors.textHint, fontSize: 11)),
        ] else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _productCard(items[i]['id']!,
              displayLabel: items[i]['label'], category: items[i]['category']),
          ),
      ]),
    );
  }
}
