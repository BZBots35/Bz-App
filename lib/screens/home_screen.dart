// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import '../services/cart_service.dart';
import '../widgets/lang_selector.dart';
import 'login_screen.dart';
import 'bzlight_presentation_screen.dart';
import 'admin_panel_screen.dart';
import 'profile_screen.dart';
import 'my_robots_screen.dart';
import 'bzvision_screen.dart';
import 'onboarding_screen.dart';
import 'pump_screen.dart';
import 'catalogue_screen.dart';
import 'storage_screen.dart';
import 'register_screen.dart';
import 'cart_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _userProducts = [];
  String _userName    = '';
  String _userInitial = '?';
  String _userRole    = AppRoles.entreprise;
  String _userStatus  = AppRoles.statusActive;
  String? _photoPath;
  int    _cartCount   = 0;
  final _authService  = AuthService();
  final _cartService  = CartService();
  final _lang         = LangService();

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user  = await _authService.getCurrentUser();
    final prefs = await SharedPreferences.getInstance();
    if (user != null && mounted) {
      final role     = await _authService.getUserRole(user.$id);
      final status   = await _authService.getUserStatus(user.$id);
      final products = await _authService.getUserProducts(user.$id);
      final count    = await _cartService.getCartCount(user.$id);
      setState(() {
        _userName     = user.name.isNotEmpty ? user.name : user.email;
        _userInitial  = _userName.isNotEmpty ? _userName[0].toUpperCase() : '?';
        _userRole     = role;
        _userStatus   = status;
        _userProducts = products;
        _photoPath    = prefs.getString('photo_path');
        _cartCount    = count;
      });

      if (status == AppRoles.statusSuspended && mounted) {
        await _authService.logout();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SuspendedScreen()),
          (_) => false,
        );
      }
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  bool get _isPending =>
      _userStatus == AppRoles.statusPending &&
      !AppRoles.hasMinimumRole(_userRole, AppRoles.distributeur);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _userRole != AppRoles.employe
        ? FloatingActionButton(
            onPressed: () async {
              await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CartScreen()));
              _loadUser(); // rafraîchit le badge
            },
            backgroundColor: const Color(0xFF0A0A0F),
            foregroundColor: Colors.white,
            elevation: 4,
            child: Stack(children: [
              const Icon(Icons.shopping_cart_outlined, size: 24),
              if (_cartCount > 0)
                Positioned(
                  right: 0, top: 0,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAB308),
                      shape: BoxShape.circle),
                    child: Center(
                      child: Text('$_cartCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900))))),
            ]))
        : null,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          if (_isPending) _buildPendingBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(_lang.t('discoverRange')),
                  const SizedBox(height: 16),
                  _buildProductGrid(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ]),
      ),
    );
  }

  // ── Bandeau compte en attente ────────────────────
  Widget _buildPendingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: Colors.orange.withOpacity(0.2)))),
      child: Row(children: [
        const Icon(Icons.hourglass_empty_rounded,
          color: Colors.orange, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _lang.t('pendingBannerText'),
            style: const TextStyle(color: Colors.orange,
              fontSize: 11, fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CatalogueScreen(
              userRole     : _userRole,
              userProducts : _userProducts))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withOpacity(0.3))),
            child: Text(_lang.t('seeAction'),
              style: const TextStyle(color: Colors.orange,
                fontSize: 10, fontWeight: FontWeight.w900)))),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────
  Widget _buildHeader() {
    final roleColor = Color(AppRoles.roleColor(_userRole));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        border: Border(bottom: BorderSide(
          color: Colors.white.withOpacity(0.1)))),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfileScreen())),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.white.withOpacity(0.3), blurRadius: 12)]),
              child: ClipOval(
                child: _photoPath != null && File(_photoPath!).existsSync()
                  ? Image.file(File(_photoPath!), fit: BoxFit.contain,
                      width: 40, height: 40)
                  : Center(child: Text(_userInitial,
                      style: const TextStyle(color: Colors.black,
                        fontWeight: FontWeight.w900, fontSize: 16))))),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lang.t('sessionActive').toUpperCase(),
                style: TextStyle(color: Colors.grey[400], fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              Row(children: [
                Text(_userName.isEmpty ? '...' : _userName,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: roleColor.withOpacity(0.4))),
                  child: Text(AppRoles.label(_userRole),
                    style: TextStyle(color: roleColor, fontSize: 8,
                      fontWeight: FontWeight.w900, letterSpacing: 1))),
              ]),
            ]),
          ]),
        ),
        const Spacer(),
        const LangSelector(),
      ]),
    );
  }

  // ── Grille produits 2x2 ──────────────────────────
  Widget _buildProductGrid() {
    final products = [
      _ProductData(_lang.t('bzlight'),
        const Color(0xFFEAB308), Icons.flash_on, 'bzlight',
        image: 'assets/bzlight.png'),
      _ProductData(_lang.t('tracteur'),
        const Color(0xFF3B82F6), Icons.directions_car, 'tracteur'),
      _ProductData(_lang.t('bzvision'),
        const Color(0xFF22D3EE), Icons.videocam, 'bzvision'),
      _ProductData(_lang.t('pompe'),
        const Color(0xFF8B5CF6), Icons.water_drop, 'pompe'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount     : 2,
        crossAxisSpacing   : 12,
        mainAxisSpacing    : 12,
        childAspectRatio   : 1.0,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(
        product : products[i],
        locked  : _isPending
          ? true
          : !AppRoles.canAccess(
              _userRole, products[i].moduleKey,
              products: _userProducts),
        onTap   : () => _navigate(products[i].moduleKey),
      ),
    );
  }

  // ── Navigation modules ───────────────────────────
  void _navigate(String module) {
    if (_isPending) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_lang.t('pendingSnackText')),
       backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating));
      return;
    }
    if (!AppRoles.canAccess(_userRole, module, products: _userProducts)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang.t('locked')),
        behavior: SnackBarBehavior.floating));
      return;
    }
    switch (module) {
      case 'bzlight':
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => BzLightPresentationScreen())); break;
      case 'bzvision':
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => BzVisionScreen())); break;
      case 'pompe':
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const PumpScreen())); break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_lang.t('inDev')),
          behavior: SnackBarBehavior.floating));
    }
  }

  // ── Bottom nav ───────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(top: BorderSide(
          color: Colors.white.withOpacity(0.08)))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _bottomNavItem(
                icon  : Icons.grid_view,
                label : _lang.t('catalog'),
                color : Colors.white,
                onTap : () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CatalogueScreen(
                    userRole     : _userRole,
                    userProducts : _userProducts)))),
              if (AppRoles.canAccessAdminPanel(_userRole) && !_isPending)
                _bottomNavItem(
                  icon  : Icons.manage_accounts,
                  label : _lang.t('accounts'),
                  color : const Color(0xFFEF4444),
                  onTap : () => Navigator.push(context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPanelScreen()))),
              _bottomNavItem(
                iconWidget: SizedBox(
                  height: 24,
                  child: Image.asset(
                    'assets/icons/bzlight_icon.png',
                    fit: BoxFit.contain,
                    color: _isPending ? Colors.grey[700] : const Color(0xFFEAB308),
                    colorBlendMode: BlendMode.srcIn)),
                label : _lang.t('myRobots'),
                color : _isPending
                  ? Colors.grey[700]!
                  : const Color(0xFFEAB308),
                onTap : _isPending
                  ? _showPendingSnack
                  : () => Navigator.push(context,
                      MaterialPageRoute(
                        builder: (_) => const MyRobotsScreen()))),
              _bottomNavItem(
                icon  : Icons.storage_outlined,
                label : _lang.t('storage'),
                color : _isPending ? Colors.grey[700]! : Colors.green,
                onTap : _isPending
                  ? _showPendingSnack
                  : () => Navigator.push(context,
                      MaterialPageRoute(
                        builder: (_) => const StorageScreen()))),
            ],
          ),
        ),
      ),
    );
  }

  void _showPendingSnack() {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_lang.t('pendingSnackText')),
      backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating));
  }

  Widget _bottomNavItem({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          SizedBox(height: 24,
            child: Center(
              child: iconWidget ?? Icon(icon!, color: color, size: 24))),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  // ── Section title ────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.white, width: 3))),
      child: Text(title.toUpperCase(),
        style: TextStyle(color: Colors.grey[400], fontSize: 11,
          fontWeight: FontWeight.w900, letterSpacing: 3)),
    );
  }

  // ── Footer ───────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        border: Border(top: BorderSide(
          color: Colors.white.withOpacity(0.1)))),
      child: Center(
        child: Text(_lang.t('legal'),
          style: TextStyle(color: Colors.grey[700], fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.5))),
    );
  }
}

// ─────────────────────────────────────────────────
// ÉCRAN COMPTE SUSPENDU
// ─────────────────────────────────────────────────
class SuspendedScreen extends StatelessWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = LangService();
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3), width: 2)),
                child: const Icon(Icons.block_outlined,
                  color: Colors.red, size: 36)),
              const SizedBox(height: 28),
              Text(lang.t('accountSuspendedTitle'),
                style: const TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              Text(lang.t('accountSuspendedDesc'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400],
                  fontSize: 14, height: 1.6)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor : Colors.white,
                    foregroundColor : Colors.black,
                    shape           : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                  child: Text(lang.t('backToLogin'),
                    style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 13, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGETS PRODUITS
// ─────────────────────────────────────────────────
class _ProductData {
  final String name, moduleKey;
  final Color color;
  final IconData icon;
  final String? image;
  const _ProductData(this.name, this.color, this.icon,
    this.moduleKey, {this.image});
}

class _ProductCard extends StatelessWidget {
  final _ProductData product;
  final bool locked;
  final VoidCallback onTap;
  const _ProductCard({
    required this.product,
    required this.locked,
    required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: locked ? 0.4 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: locked
                ? Colors.white.withOpacity(0.05)
                : product.color.withOpacity(0.2))),
          child: Stack(children: [

            // ── Image / Icône ──────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: product.image != null
                ? Image.asset(
                    product.image!,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(product.icon,
                        color: product.color.withOpacity(0.3), size: 64)))
                : Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [
                          product.color.withOpacity(0.15),
                          Colors.transparent,
                        ])),
                    child: Center(
                      child: Icon(product.icon,
                        color: product.color.withOpacity(0.5), size: 64)))),

            // ── Dégradé bas ────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.4, 1.0])))),

            // ── Nom du produit ─────────────────────
            Positioned(
              bottom: 12, left: 12, right: 12,
              child: Text(
                product.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),

            // ── Icône verrou ───────────────────────
            if (locked)
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle),
                  child: Icon(Icons.lock,
                    color: Colors.grey[500], size: 14))),

            
          ]),
        ),
      ),
    );
  }
}