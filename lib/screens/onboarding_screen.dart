// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _auth = AuthService();
  final Set<String> _selected = {};
  bool _saving = false;
  String _userName = '';

  final _products = [
    _Product(
      id:    'bzlight',
      name:  'BzLight',
      desc:  'Robot de fraisage mécanique',
      icon:  Icons.flash_on,
      color: const Color(0xFFEAB308),
      sub:   'DN100 — DN150 • Portée 26m',
    ),
    _Product(
      id:    'bzvision',
      name:  'BzVision',
      desc:  'Inspection vidéo canalisations',
      icon:  Icons.videocam,
      color: const Color(0xFF22D3EE),
      sub:   'Caméra live • Rapports PDF',
    ),
    _Product(
      id:    'tracteur',
      name:  'Tracteur',
      desc:  'Tractage câble & application résine',
      icon:  Icons.directions_car,
      color: const Color(0xFF3B82F6),
      sub:   'Modulable • Sécurité opérateur',
    ),
    _Product(
      id:    'pompe',
      name:  'Pompe résine',
      desc:  'Système d\'injection bicomposant',
      icon:  Icons.water_drop,
      color: const Color(0xFF8B5CF6),
      sub:   'Spraycoat+ • Contrôle Wi-Fi',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _auth.getCurrentUser();
    if (user != null && mounted) {
      setState(() => _userName = user.name.isNotEmpty
        ? user.name.split(' ').first : 'vous');
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sélectionnez au moins un produit'),
        behavior: SnackBarBehavior.floating));
      return;
    }

    setState(() => _saving = true);

    try {
      final user = await _auth.getCurrentUser();
      if (user != null) {
        // Sauvegarder dans users_roles via updateDocument
        await _auth.updateUserProducts(
          user.$id, _selected.toList());
      }

      // Marquer onboarding comme fait
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', true);

      if (mounted) {
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Column(children: [
              // Logo / icône BZBots
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15))),
                child: Center(
                  child: Text('BZ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 26, letterSpacing: 1)))),
              const SizedBox(height: 24),
              Text('Bienvenue, $_userName !',
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 26),
                textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'Sélectionnez les produits BZBots\nque vous possédez.',
                style: TextStyle(color: Colors.grey[500],
                  fontSize: 14, height: 1.5),
                textAlign: TextAlign.center),
            ]),
          ),

          const SizedBox(height: 32),

          // ── Grille produits ──────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.85,
                children: _products.map((p) =>
                  _buildProductCard(p)).toList(),
              ),
            ),
          ),

          // ── Bouton continuer ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(children: [
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${_selected.length} produit${_selected.length > 1 ? "s" : ""} sélectionné${_selected.length > 1 ? "s" : ""}',
                    style: TextStyle(color: Colors.grey[500],
                      fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                  child: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                    : const Text('CONTINUER',
                        style: TextStyle(fontWeight: FontWeight.w900,
                          fontSize: 14, letterSpacing: 2)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildProductCard(_Product p) {
    final isSelected = _selected.contains(p.id);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) _selected.remove(p.id);
        else            _selected.add(p.id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
            ? p.color.withOpacity(0.12)
            : const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
              ? p.color.withOpacity(0.7)
              : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1),
          boxShadow: isSelected ? [BoxShadow(
            color: p.color.withOpacity(0.2),
            blurRadius: 16)] : null,
        ),
        child: Stack(children: [
          // Checkmark
          if (isSelected)
            Positioned(top: 10, right: 10,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: p.color,
                  shape: BoxShape.circle),
                child: const Icon(Icons.check,
                  color: Colors.white, size: 13))),
          // Contenu
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: p.color.withOpacity(
                    isSelected ? 0.2 : 0.08),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(p.icon, color: p.color, size: 24)),
              const SizedBox(height: 14),
              Text(p.name, style: TextStyle(
                color: isSelected ? Colors.white : Colors.white,
                fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text(p.desc, style: TextStyle(
                color: isSelected
                  ? p.color.withOpacity(0.9)
                  : Colors.grey[600],
                fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(p.sub, style: TextStyle(
                color: Colors.grey[700], fontSize: 10)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Product {
  final String id, name, desc, sub;
  final IconData icon;
  final Color color;
  const _Product({
    required this.id, required this.name,
    required this.desc, required this.sub,
    required this.icon, required this.color,
  });
}
