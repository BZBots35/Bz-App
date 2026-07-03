// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/auth_service.dart';
import '../services/app_roles.dart';

class DistributeurPanelScreen extends StatefulWidget {
  final String distributeurId;
  final String distributeurName;

  const DistributeurPanelScreen({
    super.key,
    required this.distributeurId,
    required this.distributeurName,
  });

  @override
  State<DistributeurPanelScreen> createState() =>
      _DistributeurPanelScreenState();
}

class _DistributeurPanelScreenState extends State<DistributeurPanelScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  late TabController _tabController;

  List<models.Document> _allEntreprises     = [];
  List<models.Document> _pendingEntreprises = [];
  bool _isLoading = true;

  final List<String> _availableProducts = ['bzlight', 'pompe', 'bzvision'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchEntreprises();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEntreprises() async {
    setState(() => _isLoading = true);
    final all     = await _auth.getEntreprisesByDistributeur(
      widget.distributeurId);
    final pending = await _auth.getPendingComptes(
      distributorId: widget.distributeurId);
    setState(() {
      _allEntreprises     = all;
      _pendingEntreprises = pending;
      _isLoading          = false;
    });
  }

  // ── Valider une entreprise ───────────────────────
  Future<void> _validerEntreprise(models.Document doc) async {
    final name  = doc.data['name']  as String? ?? '';
    final email = doc.data['email'] as String? ?? '';
    final role  = doc.data['role']  as String? ?? AppRoles.entreprise;

    List<String> selectedProducts = [];

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),

              // En-tête entreprise
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF43A047).withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF43A047).withOpacity(0.3))),
                  child: Center(child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF43A047),
                      fontWeight: FontWeight.w900, fontSize: 18)))),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(email, style: TextStyle(
                      color: Colors.grey[500], fontSize: 11)),
                  ])),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Color(AppRoles.roleColor(role)).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(AppRoles.roleColor(role)).withOpacity(0.4))),
                  child: Text(AppRoles.label(role),
                    style: TextStyle(
                      color: Color(AppRoles.roleColor(role)),
                      fontSize: 10, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 24),

              // Sélection products
              Text('MODULES À ACTIVER',
                style: TextStyle(color: Colors.grey[400], fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              ..._availableProducts.map((product) {
                final isSelected = selectedProducts.contains(product);
                return GestureDetector(
                  onTap: () => setModalState(() {
                    isSelected
                      ? selectedProducts.remove(product)
                      : selectedProducts.add(product);
                  }),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                        ? const Color(0xFF1E88E5).withOpacity(0.1)
                        : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected
                        ? const Color(0xFF1E88E5).withOpacity(0.5)
                        : Colors.white.withOpacity(0.08))),
                    child: Row(children: [
                      Icon(
                        isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                        color: isSelected
                          ? const Color(0xFF1E88E5)
                          : Colors.grey[600],
                        size: 18),
                      const SizedBox(width: 12),
                      Text(product.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                            ? const Color(0xFF1E88E5)
                            : Colors.grey[400],
                          fontWeight: FontWeight.w700,
                          fontSize: 13, letterSpacing: 1)),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 20),

              // Boutons
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[400],
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Annuler',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0),
                    child: const Text('Valider',
                      style: TextStyle(fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _auth.validerCompte(
        documentId : doc.$id,
        userEmail  : email,
        userName   : name,
        products   : selectedProducts,
      );
      await _fetchEntreprises();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Entreprise validée avec succès !'),
          backgroundColor: Color(0xFF1E88E5),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ── Suspendre une entreprise ─────────────────────
  Future<void> _suspendreEntreprise(models.Document doc) async {
    final name = doc.data['name'] as String? ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Suspendre ?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text('Voulez-vous suspendre le compte de $name ?',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
              style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white),
            child: const Text('Suspendre',
              style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (confirm == true) {
      await _auth.suspendreCompte(doc.$id);
      await _fetchEntreprises();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Compte suspendu'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MES ENTREPRISES',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            Text(widget.distributeurName,
              style: TextStyle(color: Colors.grey[500],
                fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _fetchEntreprises),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1E88E5),
          indicatorWeight: 2,
          labelColor: const Color(0xFF1E88E5),
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1),
          tabs: [
            const Tab(text: 'TOUTES'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('EN ATTENTE',
                  style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, letterSpacing: 1)),
                if (_pendingEntreprises.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10)),
                    child: Text('${_pendingEntreprises.length}',
                      style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w900))),
                ],
              ]),
            ),
          ],
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF1E88E5)))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildAllEntreprises(),
              _buildPendingEntreprises(),
            ],
          ),
    );
  }

  Widget _buildAllEntreprises() {
    if (_allEntreprises.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.business_outlined, color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          Text('Aucune entreprise pour l\'instant',
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 8),
          Text('Vos entreprises apparaîtront ici après inscription',
            style: TextStyle(color: Colors.grey[700], fontSize: 12)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchEntreprises,
      color: const Color(0xFF1E88E5),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allEntreprises.length,
        itemBuilder: (_, i) => _EntrepriseTile(
          doc         : _allEntreprises[i],
          onSuspendre : () => _suspendreEntreprise(_allEntreprises[i]),
          onValider   : _allEntreprises[i].data['status'] ==
            AppRoles.statusPending
              ? () => _validerEntreprise(_allEntreprises[i])
              : null,
        ),
      ),
    );
  }

  Widget _buildPendingEntreprises() {
    if (_pendingEntreprises.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          Text('Aucune entreprise en attente',
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchEntreprises,
      color: const Color(0xFF1E88E5),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingEntreprises.length,
        itemBuilder: (_, i) => _PendingEntrepriseTile(
          doc      : _pendingEntreprises[i],
          onValider: () => _validerEntreprise(_pendingEntreprises[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile entreprise standard
// ─────────────────────────────────────────────────
class _EntrepriseTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback? onValider;
  final VoidCallback onSuspendre;
  const _EntrepriseTile({
    required this.doc,
    required this.onSuspendre,
    this.onValider});

  @override
  Widget build(BuildContext context) {
    final name     = doc.data['name']     as String? ?? 'Sans nom';
    final email    = doc.data['email']    as String? ?? '';
    final company  = doc.data['company']  as String? ?? '';
    final status   = doc.data['status']   as String? ?? AppRoles.statusPending;
    final products = (doc.data['products'] as String? ?? '')
      .split(',').where((p) => p.isNotEmpty).toList();
    final initial  = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case AppRoles.statusActive:
        statusColor = const Color(0xFF43A047);
        statusLabel = 'Actif';
        statusIcon  = Icons.check_circle_outline;
        break;
      case AppRoles.statusSuspended:
        statusColor = Colors.red;
        statusLabel = 'Suspendu';
        statusIcon  = Icons.block_outlined;
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = 'En attente';
        statusIcon  = Icons.hourglass_empty_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1E88E5).withOpacity(0.3))),
            child: Center(child: Text(initial,
              style: const TextStyle(color: Color(0xFF1E88E5),
                fontWeight: FontWeight.w900, fontSize: 18)))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
              if (company.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(company, style: TextStyle(
                  color: Colors.grey[500], fontSize: 12)),
              ],
              const SizedBox(height: 2),
              Text(email, style: TextStyle(
                color: Colors.grey[600], fontSize: 11)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(statusIcon, color: statusColor, size: 11),
                const SizedBox(width: 4),
                Text(statusLabel, style: TextStyle(
                  color: statusColor, fontSize: 10,
                  fontWeight: FontWeight.w700)),
              ]),
            ])),
          Column(children: [
            if (onValider != null)
              GestureDetector(
                onTap: onValider,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF1E88E5).withOpacity(0.4))),
                  child: const Text('Valider',
                    style: TextStyle(color: Color(0xFF1E88E5),
                      fontSize: 10, fontWeight: FontWeight.w900)))),
            if (status == AppRoles.statusActive) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onSuspendre,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withOpacity(0.3))),
                  child: const Text('Suspendre',
                    style: TextStyle(color: Colors.red,
                      fontSize: 10, fontWeight: FontWeight.w900)))),
            ],
          ]),
        ]),
        if (products.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: products.map((p) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF1E88E5).withOpacity(0.2))),
              child: Text(p.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF1E88E5),
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 1)))).toList()),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile entreprise en attente
// ─────────────────────────────────────────────────
class _PendingEntrepriseTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback onValider;
  const _PendingEntrepriseTile({required this.doc, required this.onValider});

  @override
  Widget build(BuildContext context) {
    final name    = doc.data['name']    as String? ?? 'Sans nom';
    final email   = doc.data['email']   as String? ?? '';
    final company = doc.data['company'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orange.withOpacity(0.3))),
            child: Center(child: Text(initial,
              style: const TextStyle(color: Colors.orange,
                fontWeight: FontWeight.w900, fontSize: 18)))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
              if (company.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(company, style: TextStyle(
                  color: Colors.grey[500], fontSize: 12)),
              ],
              const SizedBox(height: 2),
              Text(email, style: TextStyle(
                color: Colors.grey[600], fontSize: 11)),
            ])),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onValider,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Valider cette entreprise',
              style: TextStyle(fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              elevation: 0),
          ),
        ),
      ]),
    );
  }
}