// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/bzvision_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';
import 'bzvision_map_screen.dart';
import 'bzvision_chantier_screen.dart';

class BzVisionScreen extends StatefulWidget {
  const BzVisionScreen({super.key});
  @override
  State<BzVisionScreen> createState() => _BzVisionScreenState();
}

class _BzVisionScreenState extends State<BzVisionScreen> {
  final _auth    = AuthService();
  final _service = BzVisionService();
  final _lang    = LangService();
  List<models.Document> _chantiers = [];
  bool   _loading   = true;
  bool   _fromCache = false;
  final  _searchCtrl  = TextEditingController();
  String _searchQuery = '';
  String _userRole  = 'client';
  String _userId    = '';
  String _userName  = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    _loadData();
  }


  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final user = await _auth.getCurrentUser();
      if (user != null) {
        final role = await _auth.getUserRole(user.$id);
        try {
          final list = await _service.getChantiers(user.$id, role);
          // Sauvegarde en cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('bzvision_userId',   user.$id);
          await prefs.setString('bzvision_userName',  user.name);
          await prefs.setString('bzvision_userRole',  role);
          await prefs.setString('bzvision_chantiers',
            jsonEncode(list.map((d) => {'id': d.$id, 'data': d.data}).toList()));
          if (mounted) setState(() {
            _userId    = user.$id;
            _userName  = user.name;
            _userRole  = role;
            _chantiers = list;
            _fromCache = false;
            _loading   = false;
          });
        } catch (_) {
          await _loadFromCache(user.$id, user.name, role);
        }
      } else {
        await _loadFromCache('', '', '');
      }
    } catch (_) {
      // getCurrentUser ou getUserRole a timeout → cache
      await _loadFromCache('', '', '');
    }
  }

  Future<void> _loadFromCache(String userId, String userName, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUserId   = prefs.getString('bzvision_userId')   ?? userId;
    final cachedUserName = prefs.getString('bzvision_userName')  ?? userName;
    final cachedRole     = prefs.getString('bzvision_userRole')  ?? role;
    final raw            = prefs.getString('bzvision_chantiers') ?? '[]';
    final List<dynamic> decoded = jsonDecode(raw);
    // Reconstruit des documents simulés à partir du cache JSON
    final cached = decoded.map<models.Document>((e) {
      return models.Document.fromMap({
        '\$id':             e['id'],
        '\$collectionId':   '',
        '\$databaseId':     '',
        '\$createdAt':      '',
        '\$updatedAt':      '',
        '\$permissions':    [],
        ...Map<String, dynamic>.from(e['data']),
      });
    }).toList();
    if (mounted) setState(() {
      _userId    = cachedUserId;
      _userName  = cachedUserName;
      _userRole  = cachedRole;
      _chantiers = cached;
      _fromCache = true;
      _loading   = false;
    });
  }

  Future<void> _showCreateChantier() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateChantierSheet(),
    );
    if (result != null) {
      final company = await _auth.getUserCompany(_userId);
      await _service.createChantier(
        nom:     result['nom']!,
        adresse: result['adresse']!,
        client:  result['client']!,
        date:    DateTime.now().toIso8601String().substring(0, 10),
        statut:  'en_cours',
        userId:  _userId,
        company: company,
      );
      _loadData();
    }
  }

  Future<void> _deleteChantier(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Text(_lang.t('deleteQuestion'), style: const TextStyle(color: Colors.white)),
        content: Text(_lang.t('deleteWorksiteConfirm'),
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text(_lang.t('cancel'), style: const TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: Text(_lang.t('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteChantier(docId);
      _loadData();
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
        title: Row(children: [
          const Text('BZVISION',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
              letterSpacing: 2, fontSize: 15)),
          if (_fromCache) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withOpacity(0.4))),
              child: const Text('CACHE', style: TextStyle(
                color: Colors.orange, fontSize: 9, fontWeight: FontWeight.w900,
                letterSpacing: 1)),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined,
              color: Color(0xFF22D3EE), size: 20),
            tooltip: 'Carte',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => BzVisionMapScreen(chantiers: _chantiers)))),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadData),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
        : Column(children: [
            // ── Header stats ──────────────────────
            _buildStats(),
            // ── Liste chantiers ───────────────────
            Expanded(
              child: Column(children: [
                // ── Barre de recherche ────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '🔍  Nom, ville, client, date...',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF22D3EE), size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey, size: 16),
                            onPressed: () => _searchCtrl.clear())
                        : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
                  )),
                const SizedBox(height: 8),
                // ── Liste ─────────────────────────
                Expanded(
                  child: _filteredChantiers.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: const Color(0xFF22D3EE),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredChantiers.length,
                          itemBuilder: (_, i) => _buildChantierCard(_filteredChantiers[i]),
                        ),
                      ),
                ),
              ]),
            ),
          ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_worksite',
        onPressed: _showCreateChantier,
        backgroundColor: const Color(0xFF22D3EE),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(_lang.t('newWorksite'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  List<models.Document> get _filteredChantiers {
    if (_searchQuery.isEmpty) return _chantiers;
    return _chantiers.where((c) {
      final d = c.data;
      return (d['nom']     as String? ?? '').toLowerCase().contains(_searchQuery) ||
             (d['adresse'] as String? ?? '').toLowerCase().contains(_searchQuery) ||
             (d['client']  as String? ?? '').toLowerCase().contains(_searchQuery) ||
             (d['date']    as String? ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Widget _buildStats() {
    final enCours  = _chantiers.where((c) => c.data['statut'] == 'en_cours').length;
    final termines = _chantiers.where((c) => c.data['statut'] == 'termine').length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06)))),
      child: Row(children: [
        _statBox(_lang.t('total'), '${_chantiers.length}', Colors.white),
        const SizedBox(width: 12),
        _statBox(_lang.t('inProgress'), '$enCours', const Color(0xFF22D3EE)),
        const SizedBox(width: 12),
        _statBox(_lang.t('completed'), '$termines', const Color(0xFF22D3EE).withOpacity(0.5)),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Text(value, style: TextStyle(color: color,
            fontWeight: FontWeight.w900, fontSize: 22)),
          Text(label, style: TextStyle(color: color.withOpacity(0.7),
            fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF22D3EE).withOpacity(0.1), shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2))),
        child: Icon(Icons.videocam_outlined,
          color: const Color(0xFF22D3EE).withOpacity(0.5), size: 36)),
      const SizedBox(height: 20),
      Text(_lang.t('noWorksite'), style: const TextStyle(color: Colors.white,
        fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      Text(_lang.t('tapToCreateFirstWorksite'),
        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 80),
    ]));
  }

  Widget _buildChantierCard(models.Document doc) {
    final nom     = doc.data['nom']     as String? ?? '';
    final adresse = doc.data['adresse'] as String? ?? '';
    final client  = doc.data['client']  as String? ?? '';
    final date    = doc.data['date']    as String? ?? '';
    final statut  = doc.data['statut']  as String? ?? 'en_cours';
    final isEnCours = statut == 'en_cours';
    final statusColor = isEnCours ? const Color(0xFF22D3EE) : Colors.grey;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => BzVisionChantierScreen(
          chantierDoc: doc, userRole: _userRole, userId: _userId, userName: _userName))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withOpacity(0.2)),
          boxShadow: [BoxShadow(
            color: statusColor.withOpacity(0.05), blurRadius: 12)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nom, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 16))),
            // Badge statut
            GestureDetector(
              onTap: () async {
                final newStatut = isEnCours ? 'termine' : 'en_cours';
                await _service.updateChantierStatut(doc.$id, newStatut);
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.3))),
                child: Text(isEnCours ? _lang.t('inProgress') : _lang.t('completed'),
                  style: TextStyle(color: statusColor, fontSize: 10,
                    fontWeight: FontWeight.w900)),
              ),
            ),
            // Supprimer (admin/super_admin uniquement)
            if (_userRole == AppRoles.superAdmin || _userRole == AppRoles.admin)
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[800], size: 18),
                onPressed: () => _deleteChantier(doc.$id),
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.location_on_outlined, color: Colors.grey[600], size: 13),
            const SizedBox(width: 4),
            Expanded(child: Text(adresse, style: TextStyle(color: Colors.grey[500],
              fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.business_outlined, color: Colors.grey[600], size: 13),
            const SizedBox(width: 4),
            Text(client, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const Spacer(),
            Icon(Icons.calendar_today_outlined, color: Colors.grey[700], size: 11),
            const SizedBox(width: 4),
            Text(date, style: TextStyle(color: Colors.grey[700], fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

// ── Formulaire création chantier ─────────────────
class _CreateChantierSheet extends StatefulWidget {
  const _CreateChantierSheet();
  @override
  State<_CreateChantierSheet> createState() => _CreateChantierSheetState();
}

class _CreateChantierSheetState extends State<_CreateChantierSheet> {
  final _lang = LangService();
  final _nomCtrl     = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _clientCtrl  = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(_lang.t('newWorksite').toUpperCase(), style: const TextStyle(color: Colors.white,
          fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
        const SizedBox(height: 20),
        _field(_nomCtrl, _lang.t('worksiteName'), Icons.construction_outlined),
        const SizedBox(height: 12),
        _field(_adresseCtrl, _lang.t('address'), Icons.location_on_outlined),
        const SizedBox(height: 12),
        _field(_clientCtrl, _lang.t('client'), Icons.business_outlined),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: () {
              if (_nomCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'nom':     _nomCtrl.text.trim(),
                'adresse': _adresseCtrl.text.trim(),
                'client':  _clientCtrl.text.trim(),
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE), foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(_lang.t('create').toUpperCase(), style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 18),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}
