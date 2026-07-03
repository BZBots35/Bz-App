// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/bzlight_parts_service.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/lang_service.dart';
import '../services/app_roles.dart';
import '../widgets/lang_selector.dart';
import 'cart_badge.dart';

class BzlightPartsScreen extends StatefulWidget {
  const BzlightPartsScreen({super.key});
  @override
  State<BzlightPartsScreen> createState() => _BzlightPartsScreenState();
}

class _BzlightPartsScreenState extends State<BzlightPartsScreen> {
  final _partsService = BzlightPartsService();
  final _cartService  = CartService();
  final _authService  = AuthService();
  final _lang         = LangService();

  final List<String> _series = ['BZL1', 'BZL2', 'BZL3', 'BZL4'];
  String _selectedSeries = 'BZL2';

  List<models.Document> _parts      = [];
  List<String>          _assemblies = [];
  Set<String>           _expanded   = {};
  bool   _loading     = true;
  String _userId      = '';
  String _robotSerial = '';
  String _userRole    = '';

  bool get _canEditVersion =>
      AppRoles.hasMinimumRole(_userRole, AppRoles.distributeur);

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      final role = await _authService.getUserRole(user.$id);
      setState(() {
        _userId      = user.$id;
        _robotSerial = _selectedSeries;
        _userRole    = role;
      });
    }
    await _loadParts();
  }

  Future<void> _loadParts() async {
    setState(() => _loading = true);
    final parts      = await _partsService.getPartsBySeries(_selectedSeries);
    final assemblies = await _partsService.getAssembliesBySeries(_selectedSeries);
    setState(() {
      _parts      = parts;
      _assemblies = assemblies;
      _expanded   = {if (assemblies.isNotEmpty) assemblies.first};
      _loading    = false;
    });
  }

  Future<void> _addToCart(models.Document part) async {
    if (_userId.isEmpty) return;
    final name      = part.data['name']      as String? ?? '';
    final reference = part.data['reference'] as String? ?? '';

    await _cartService.addItem(
      _userId,
      CartItem(
        id          : reference,
        name        : name,
        version     : _selectedSeries,
        robotSerial : _robotSerial,
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ $name ajouté au panier'),
        backgroundColor: const Color(0xFFEAB308),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
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
        title: const Text('BZLIGHT — PIÈCES',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
        actions: [
          CartBadge(),
          const LangSelector(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [

        // ── Sélecteur de série ───────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            border: Border(bottom: BorderSide(
              color: Colors.white.withOpacity(0.06)))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SÉRIE',
                style: TextStyle(color: Colors.grey[500], fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 10),
              Row(children: _series.map((s) => Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSeries = s;
                      _robotSerial    = s;
                    });
                    _loadParts();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedSeries == s
                        ? const Color(0xFFEAB308).withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedSeries == s
                          ? const Color(0xFFEAB308)
                          : Colors.white.withOpacity(0.08),
                        width: _selectedSeries == s ? 1.5 : 1)),
                    child: Text(s,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedSeries == s
                          ? const Color(0xFFEAB308)
                          : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                  ),
                ),
              )).toList()),
            ],
          ),
        ),

        // ── Liste des pièces ─────────────────────
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: Color(0xFFEAB308)))
            : _parts.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _assemblies.length,
                  itemBuilder: (_, i) => _buildAssemblySection(
                    _assemblies[i])),
        ),
      ]),
    );
  }

  // ── Section sous-assemblage ──────────────────────
  Widget _buildAssemblySection(String assembly) {
    final isExpanded = _expanded.contains(assembly);
    final parts = _parts.where(
      (p) => p.data['assembly'] == assembly).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
            ? const Color(0xFFEAB308).withOpacity(0.3)
            : Colors.white.withOpacity(0.06))),
      child: Column(children: [

        // ── Header accordéon ──────────────────────
        GestureDetector(
          onTap: () => setState(() {
            isExpanded
              ? _expanded.remove(assembly)
              : _expanded.add(assembly);
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isExpanded
                ? const Color(0xFFEAB308).withOpacity(0.05)
                : Colors.transparent,
              borderRadius: BorderRadius.only(
                topLeft    : const Radius.circular(16),
                topRight   : const Radius.circular(16),
                bottomLeft : Radius.circular(isExpanded ? 0 : 16),
                bottomRight: Radius.circular(isExpanded ? 0 : 16))),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.build_outlined,
                  color: Color(0xFFEAB308), size: 16)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(assembly,
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 14)),
                  Text('${parts.length} pièce${parts.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Colors.grey[600], fontSize: 11)),
                ])),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: isExpanded
                  ? const Color(0xFFEAB308)
                  : Colors.grey[600],
                size: 20),
            ]),
          ),
        ),

        // ── Pièces ────────────────────────────────
        if (isExpanded)
          ...parts.map((part) => _buildPartTile(part, parts.last.$id == part.$id)),
      ]),
    );
  }

  // ── Tuile pièce ──────────────────────────────────
  Widget _buildPartTile(models.Document part, bool isLast) {
    final name      = part.data['name']        as String? ?? '';
    final reference = part.data['reference']   as String? ?? '';
    final desc      = part.data['description'] as String? ?? '';
    final imageUrl  = part.data['image_url']   as String? ?? '';
    final version   = part.data['version']     as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: Row(children: [

        // Photo ou icône
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEAB308).withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFEAB308).withOpacity(0.15))),
          child: imageUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.settings_outlined,
                    color: Color(0xFFEAB308), size: 24)))
            : const Icon(Icons.settings_outlined,
                color: Color(0xFFEAB308), size: 24)),
        const SizedBox(width: 12),

        // Infos
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(reference,
                  style: const TextStyle(
                    color: Color(0xFFEAB308),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5))),
              if (version.isNotEmpty || _canEditVersion) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _canEditVersion ? () => _editVersion(part) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _canEditVersion
                          ? const Color(0xFFEAB308).withOpacity(0.4)
                          : Colors.white.withOpacity(0.15))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(version.isEmpty ? '—' : version,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                      if (_canEditVersion) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.edit, size: 10, color: Colors.grey[500]),
                      ],
                    ]),
                  ),
                ),
              ],
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc,
                style: TextStyle(
                  color: Colors.grey[600], fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            ],
          ])),
        const SizedBox(width: 8),

        // Bouton panier
        GestureDetector(
          onTap: () => _addToCart(part),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFEAB308).withOpacity(0.4))),
            child: const Icon(Icons.add_shopping_cart,
              color: Color(0xFFEAB308), size: 18))),
      ]),
    );
  }

  Future<void> _editVersion(models.Document part) async {
    final currentVersion = part.data['version'] as String? ?? '';
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
      await _partsService.updatePartVersion(part.$id, newVersion);
      await _loadParts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('❌ Échec de la mise à jour'),
          backgroundColor: Colors.red[800]));
      }
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.build_outlined, color: Colors.grey[700], size: 48),
        const SizedBox(height: 12),
        Text('Aucune pièce pour $_selectedSeries',
          style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        const SizedBox(height: 8),
        Text('Les pièces seront ajoutées prochainement',
          style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      ]),
    );
  }
}