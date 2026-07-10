//test
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _lang        = LangService();

  late TabController _tabController;

  List<models.Document> _allUsers     = [];
  List<models.Document> _pendingUsers = [];
  bool _isLoading = true;

  final List<String> _availableProducts = ['bzlight', 'pompe', 'bzvision'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _lang.addListener(() { if (mounted) setState(() {}); });
    _fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    final all     = await _authService.getAllUsersRoles();
    final pending = await _authService.getPendingComptes();
    setState(() {
      _allUsers     = all;
      _pendingUsers = pending;
      _isLoading    = false;
    });
  }

  Future<void> _changeUserRole(String documentId, String currentRole) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(_lang.t('changeRole'),
              style: TextStyle(color: Colors.grey[400], fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 16),
            ...AppRoles.all.map((role) {
              final c         = Color(AppRoles.roleColor(role));
              final isCurrent = role == currentRole;
              return GestureDetector(
                onTap: () => Navigator.pop(context, role),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isCurrent
                      ? c.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isCurrent
                      ? c.withOpacity(0.5)
                      : Colors.white.withOpacity(0.08))),
                  child: Row(children: [
                    Container(width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Text(AppRoles.label(role),
                      style: TextStyle(
                        color: isCurrent ? c : Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    if (isCurrent)
                      Icon(Icons.check_circle, color: c, size: 18),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && selected != currentRole) {
      await _authService.updateRole(documentId, selected);
      await _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${_lang.t("roleUpdated")} : ${AppRoles.label(selected)}'),
          backgroundColor: Color(AppRoles.roleColor(selected)),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _validerCompte(models.Document doc) async {
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

              Text(_lang.t('modulesToActivate'),
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
                        ? const Color(0xFF22D3EE).withOpacity(0.1)
                        : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected
                        ? const Color(0xFF22D3EE).withOpacity(0.5)
                        : Colors.white.withOpacity(0.08))),
                    child: Row(children: [
                      Icon(
                        isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                        color: isSelected
                          ? const Color(0xFF22D3EE)
                          : Colors.grey[600],
                        size: 18),
                      const SizedBox(width: 12),
                      Text(product.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                            ? const Color(0xFF22D3EE)
                            : Colors.grey[400],
                          fontWeight: FontWeight.w700,
                          fontSize: 13, letterSpacing: 1)),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 20),

              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[400],
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(_lang.t('cancelBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0),
                    child: Text(_lang.t('validateBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w900,
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
      await _authService.validerCompte(
        documentId : doc.$id,
        userEmail  : email,
        userName   : name,
        products   : selectedProducts,
      );
      await _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_lang.t('accountValidated')),
          backgroundColor: const Color(0xFF43A047),
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
        title: Text(_lang.t('adminPanel'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _fetchUsers),
          const LangSelector(),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF22D3EE),
          indicatorWeight: 2,
          labelColor: const Color(0xFF22D3EE),
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1),
          tabs: [
            Tab(text: _lang.t('allAccounts')),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_lang.t('pendingAccounts'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12, letterSpacing: 1)),
                if (_pendingUsers.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10)),
                    child: Text('${_pendingUsers.length}',
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
            color: Color(0xFF22D3EE)))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildAllUsers(),
              _buildPendingUsers(),
            ],
          ),
    );
  }

  Widget _buildAllUsers() {
    if (_allUsers.isEmpty) {
      return Center(child: Text(_lang.t('noUsers'),
        style: TextStyle(color: Colors.grey[600], fontSize: 14)));
    }
    return RefreshIndicator(
      onRefresh: _fetchUsers,
      color: const Color(0xFF22D3EE),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allUsers.length,
        itemBuilder: (_, i) => _UserTile(
          doc       : _allUsers[i],
          onRoleTap : () => _changeUserRole(
            _allUsers[i].$id,
            _allUsers[i].data['role'] as String? ?? AppRoles.entreprise),
          showStatus: true,
          lang      : _lang,
        ),
      ),
    );
  }

  Widget _buildPendingUsers() {
    if (_pendingUsers.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline,
            color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          Text(_lang.t('noPendingAccounts'),
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchUsers,
      color: const Color(0xFF22D3EE),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingUsers.length,
        itemBuilder: (_, i) => _PendingTile(
          doc      : _pendingUsers[i],
          onValider: () => _validerCompte(_pendingUsers[i]),
          lang     : _lang,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile utilisateur standard
// ─────────────────────────────────────────────────
class _UserTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback onRoleTap;
  final bool showStatus;
  final LangService lang;
  const _UserTile({
    required this.doc,
    required this.onRoleTap,
    required this.lang,
    this.showStatus = false});

  @override
  Widget build(BuildContext context) {
    final name      = doc.data['name']    as String? ?? '';
    final email     = doc.data['email']   as String? ?? '';
    final role      = doc.data['role']    as String? ?? AppRoles.entreprise;
    final status    = doc.data['status']  as String? ?? AppRoles.statusPending;
    final company   = doc.data['company'] as String? ?? '';
    final roleColor = Color(AppRoles.roleColor(role));
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: roleColor.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: roleColor.withOpacity(0.3))),
          child: Center(child: Text(initial,
            style: TextStyle(color: roleColor,
              fontWeight: FontWeight.w900, fontSize: 18)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isNotEmpty ? name : lang.t('noName'),
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(email, style: TextStyle(
              color: Colors.grey[600], fontSize: 11)),
            if (company.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(company, style: TextStyle(
                color: Colors.grey[700], fontSize: 10)),
            ],
            if (showStatus) ...[
              const SizedBox(height: 4),
              _StatusBadge(status: status, lang: lang),
            ],
          ])),
        GestureDetector(
          onTap: onRoleTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: roleColor.withOpacity(0.4))),
            child: Row(children: [
              Text(AppRoles.label(role),
                style: TextStyle(color: roleColor,
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, color: roleColor, size: 14),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGET — Tuile compte en attente
// ─────────────────────────────────────────────────
class _PendingTile extends StatelessWidget {
  final models.Document doc;
  final VoidCallback onValider;
  final LangService lang;
  const _PendingTile({
    required this.doc,
    required this.onValider,
    required this.lang});

  @override
  Widget build(BuildContext context) {
    final name    = doc.data['name']    as String? ?? '';
    final email   = doc.data['email']   as String? ?? '';
    final role    = doc.data['role']    as String? ?? AppRoles.entreprise;
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
              Text(name.isNotEmpty ? name : lang.t('noName'),
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(email, style: TextStyle(
                color: Colors.grey[600], fontSize: 11)),
              if (company.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(company, style: TextStyle(
                  color: Colors.grey[700], fontSize: 10)),
              ],
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onValider,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(lang.t('validateAccount'),
              style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 12, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
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

// ─────────────────────────────────────────────────
// WIDGET — Badge de statut
// ─────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final LangService lang;
  const _StatusBadge({required this.status, required this.lang});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case AppRoles.statusActive:
        color = const Color(0xFF43A047);
        label = lang.t('statusActiveDisplay');
        icon  = Icons.check_circle_outline;
        break;
      case AppRoles.statusSuspended:
        color = Colors.red;
        label = lang.t('statusSuspendedDisplay');
        icon  = Icons.block_outlined;
        break;
      default:
        color = Colors.orange;
        label = lang.t('statusPendingDisplay');
        icon  = Icons.hourglass_empty_rounded;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 11),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color,
        fontSize: 10, fontWeight: FontWeight.w700)),
    ]);
  }
}