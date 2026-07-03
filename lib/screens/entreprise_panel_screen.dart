// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/auth_service.dart';
import '../services/app_roles.dart';

class EntreprisePanelScreen extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseName;
  final List<String> entrepriseProducts;

  const EntreprisePanelScreen({
    super.key,
    required this.entrepriseId,
    required this.entrepriseName,
    required this.entrepriseProducts,
  });

  @override
  State<EntreprisePanelScreen> createState() => _EntreprisePanelScreenState();
}

class _EntreprisePanelScreenState extends State<EntreprisePanelScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  late TabController _tabController;

  List<models.Document> _allEmployes     = [];
  List<models.Document> _pendingEmployes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchEmployes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployes() async {
    setState(() => _isLoading = true);
    final all     = await _auth.getEmployesByEntreprise(widget.entrepriseId);
    final pending = all.where((e) =>
      e.data['status'] == AppRoles.statusPending).toList();
    setState(() {
      _allEmployes     = all;
      _pendingEmployes = pending;
      _isLoading       = false;
    });
  }

  // ── Valider un employé ───────────────────────────
  Future<void> _validerEmploye(models.Document doc) async {
    final name  = doc.data['name']  as String? ?? '';
    final email = doc.data['email'] as String? ?? '';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),

            // En-tête employé
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF8E24AA).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF8E24AA).withOpacity(0.3))),
                child: Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF8E24AA),
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
            ]),
            const SizedBox(height: 20),

            // Info products hérités
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MODULES ACTIVÉS',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10,
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  widget.entrepriseProducts.isEmpty
                    ? Text('Aucun module',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12))
                    : Wrap(
                        spacing: 6, runSpacing: 6,
                        children: widget.entrepriseProducts.map((p) =>
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22D3EE).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF22D3EE).withOpacity(0.3))),
                            child: Text(p.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF22D3EE),
                                fontSize: 10, fontWeight: FontWeight.w900,
                                letterSpacing: 1)))).toList()),
                  const SizedBox(height: 6),
                  Text('L\'employé héritera de ces modules automatiquement.',
                    style: TextStyle(color: Colors.grey[600],
                      fontSize: 10, fontStyle: FontStyle.italic)),
                ]),
            ),
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
                    backgroundColor: const Color(0xFF8E24AA),
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
    );

    if (confirmed == true) {
      await _auth.validerCompte(
        documentId : doc.$id,
        userEmail  : email,
        userName   : name,
        products   : widget.entrepriseProducts,
      );
      await _fetchEmployes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Employé validé avec succès !'),
          backgroundColor: Color(0xFF8E24AA),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ── Suspendre un employé ─────────────────────────
  Future<void> _suspendreEmploye(models.Document doc) async {
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
      await _fetchEmployes();
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
            const Text('MES EMPLOYÉS',
              style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            Text(widget.entrepriseName,
              style: TextStyle(color: Colors.grey[500],
                fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _fetchEmployes),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8E24AA),
          indicatorWeight: 2,
          labelColor: const Color(0xFF8E24AA),
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1),
          tabs: [
            const Tab(text: 'TOUS'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('EN ATTENTE',
                  style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12, letterSpacing: 1)),
                if (_pendingEmployes.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10)),
                    child: Text('${_pendingEmployes.length}',
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
            color: Color(0xFF8E24AA)))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildAllEmployes(),
              _buildPendingEmployes(),
            ],
          ),
    );
  }

  // ── Tous les employés ────────────────────────────
  Widget _buildAllEmployes() {
    if (_allEmployes.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.badge_outlined, color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          Text('Aucun employé pour l\'instant',
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 8),
          Text('Vos employés apparaîtront ici après inscription',
            style: TextStyle(color: Colors.grey[700], fontSize: 12)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchEmployes,
      color: const Color(0xFF8E24AA),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allEmployes.length,
        itemBuilder: (_, i) => _EmployeTile(
          doc          : _allEmployes[i],
          onSuspendre  : () => _suspendreEmploye(_allEmployes[i]),
          onValider    : _allEmployes[i].data['status'] ==
            AppRoles.statusPending
              ? () => _validerEmploye(_allEmployes[i])
              : null,
        ),
      ),
    );
  }

  // ── Employés en attente ──────────────────────────
  Widget _buildPendingEmployes() {
    if (_pendingEmployes.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline,
            color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          Text('Aucun employé en attente',
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchEmployes,
      color: const Color(0xFF8E24AA),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingEmployes.length,
        itemBuilder: (_, i) => _PendingEmployeTile(
          doc      : _pendingEmployes[i],
          onValider: () => _validerEmploye(_pendingEmployes[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile employé standard
// ─────────────────────────────────────────────────
class _EmployeTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback? onValider;
  final VoidCallback onSuspendre;
  const _EmployeTile({
    required this.doc,
    required this.onSuspendre,
    this.onValider});

  @override
  Widget build(BuildContext context) {
    final name    = doc.data['name']    as String? ?? 'Sans nom';
    final email   = doc.data['email']   as String? ?? '';
    final status  = doc.data['status']  as String? ?? AppRoles.statusPending;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

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
      child: Row(children: [
        // Avatar
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF8E24AA).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF8E24AA).withOpacity(0.3))),
          child: Center(child: Text(initial,
            style: const TextStyle(color: Color(0xFF8E24AA),
              fontWeight: FontWeight.w900, fontSize: 18)))),
        const SizedBox(width: 12),

        // Infos
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 14)),
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

        // Actions
        Column(children: [
          if (onValider != null)
            GestureDetector(
              onTap: onValider,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8E24AA).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF8E24AA).withOpacity(0.4))),
                child: const Text('Valider',
                  style: TextStyle(color: Color(0xFF8E24AA),
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
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile employé en attente
// ─────────────────────────────────────────────────
class _PendingEmployeTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback onValider;
  const _PendingEmployeTile({required this.doc, required this.onValider});

  @override
  Widget build(BuildContext context) {
    final name    = doc.data['name']  as String? ?? 'Sans nom';
    final email   = doc.data['email'] as String? ?? '';
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
            label: const Text('Valider cet employé',
              style: TextStyle(fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E24AA),
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