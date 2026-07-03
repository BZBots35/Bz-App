// ignore_for_file: deprecated_member_use
// ignore_for_file: unused_field
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/robot_service.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';
import 'bzlight_dashboard_screen.dart';
import 'bzlight_screen.dart';
import 'bz_tutorial.dart';

class MyRobotsScreen extends StatefulWidget {
  const MyRobotsScreen({super.key});
  @override
  State<MyRobotsScreen> createState() => _MyRobotsScreenState();
}

class _MyRobotsScreenState extends State<MyRobotsScreen> {
  final _auth        = AuthService();
  final _robots      = RobotService();
  final _lang        = LangService();
  final _tutorialKey = GlobalKey<BzTutorialState>();

  List<TutorialStep> get _tutorialSteps => [];
  List<models.Document> _list = [];
  bool   _loading     = true;
  String _userRole    = 'client';
  String _userCompany = '';

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadRobots();
  }

  Future<void> _loadRobots() async {
    setState(() => _loading = true);
    final user = await _auth.getCurrentUser();
    if (user != null) {
      final role    = await _auth.getUserRole(user.$id);
      final company = await _auth.getUserCompany(user.$id);
      List<models.Document> list;

      if (role == AppRoles.superAdmin || role == AppRoles.admin) {
        // Admin/super_admin → tous les robots de toutes les entreprises
        list = await _robots.getAllRobots();
      } else if (company.isNotEmpty) {
        // Client avec entreprise → tous les robots de son entreprise
        list = await _robots.getCompanyRobots(company);
      } else {
        // Fallback : pas d'entreprise renseignée → robots personnels uniquement
        list = await _robots.getUserRobots(user.$id);
      }

      if (mounted) setState(() {
        _list        = list;
        _userRole    = role;
        _userCompany = company;
        _loading     = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _openRobot(models.Document doc) {
    final serial  = doc.data['serial']  as String;
    final company = doc.data['company'] as String;
    final serie   = doc.data['serie']   as int;
    final year    = doc.data['year']    as String;
    final number  = doc.data['number']  as int;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BzLightDashboardScreen(
        serial: serial, serie: serie, year: year,
        number: number, company: company)));
  }

  String get _screenTitle {
    if (_userRole == AppRoles.superAdmin || _userRole == AppRoles.admin) {
      return _lang.t('allRobots');
    }
    if (_userCompany.isNotEmpty) {
      return '${_lang.t('companyRobots')} ${_userCompany.toUpperCase()}';
    }
    return _lang.t('myRobotsTitle');
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
        title: Text(_screenTitle,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
            letterSpacing: 2, fontSize: 15)),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white54, size: 20), onPressed: () => _tutorialKey.currentState?.show()),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadRobots),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: BzTutorial(key: _tutorialKey, tutorialKey: 'bzlight_my_robots', steps: _tutorialSteps, child: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFEAB308)))
        : _list.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _loadRobots,
              color: const Color(0xFFEAB308),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _list.length,
                itemBuilder: (_, i) => _buildRobotCard(_list[i]),
              ),
            )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BzLightScreen()));
          _loadRobots();
        },
        backgroundColor: const Color(0xFFEAB308),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(_lang.t('addRobotBtn'),
        style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFEAB308).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.2))),
          child: Center(
            child: Image.asset('assets/icons/bzlight_icon.png',
              width: 40, height: 40,
              color: const Color(0xFFEAB308).withOpacity(0.5),
              colorBlendMode: BlendMode.srcIn))),
        const SizedBox(height: 20),
        const Text('Aucun robot enregistré',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        Text('Appuyez sur + pour associer votre premier robot',
          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _buildRobotCard(models.Document doc) {
    final serial  = doc.data['serial']  as String;
    final company = doc.data['company'] as String;
    final serie   = doc.data['serie']   as int;

    return GestureDetector(
      onTap: () => _openRobot(doc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.25)),
          boxShadow: [BoxShadow(
            color: const Color(0xFFEAB308).withOpacity(0.06), blurRadius: 16)],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.3))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Image.asset('assets/icons/bzlight_icon.png',
                width: 40, height: 40,
                color: const Color(0xFFEAB308),
                colorBlendMode: BlendMode.srcIn),
              Text('S$serie', style: const TextStyle(color: Color(0xFFEAB308),
                fontSize: 9, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(serial, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5,
                fontFamily: 'monospace')),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.business, color: Colors.grey[600], size: 12),
                const SizedBox(width: 4),
                Text(company, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ]),
            ],
          )),
          // Bouton historique (distributeurs + admins)
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.chevron_right,
              color: Color(0xFFEAB308), size: 18)),
        ]),
      ),
    );
  }
}


// ══════════════════════════════════════════════════
// ÉCRAN HISTORIQUE ROBOT
// ══════════════════════════════════════════════════
class RobotHistoryScreen extends StatefulWidget {
  final models.Document doc;
  final String userRole;
  const RobotHistoryScreen({required this.doc, required this.userRole});
  @override
  State<RobotHistoryScreen> createState() => _RobotHistoryScreenState();
}

class _RobotHistoryScreenState extends State<RobotHistoryScreen> {
  final _robots = RobotService();
  final _lang   = LangService();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final h = await _robots.getHistory(widget.doc.$id);
    if (mounted) setState(() { _history = h; _loading = false; });
  }

  void _showAddEntry({Map<String, dynamic>? editEntry}) {
    final isEdit     = editEntry != null;
    final typeCtrl    = TextEditingController(text: editEntry?['type'] ?? '');
    final selectedPieces = ((editEntry?['piece'] as String?) ?? '')
        .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final techCtrl    = TextEditingController(text: editEntry?['technicien'] ?? '');
    final clientCtrl  = TextEditingController(text: editEntry?['client'] ?? '');
    final descCtrl    = TextEditingController(text: editEntry?['description'] ?? '');
    final List<Uint8List> imageBytesList = [];
    final List<String> imageNamesList = [];
    // Images déjà existantes (mode édition) — conservées par fileId
    final List<String> existingImageIds =
        ((editEntry?['images'] as List?)?.cast<String>() ?? []).toList();
    final picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: false, // ← ne se ferme que via la croix ou Enregistrer
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool saving = false;
          return Dialog(
            backgroundColor: const Color(0xFF0A0A0F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: Text(
                    isEdit ? _lang.t('historyEditEntry') : _lang.t('historyNewEntry'),
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 16))),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(Icons.close, color: Colors.grey[600], size: 20)),
                ]),
                const SizedBox(height: 16),
                _field(typeCtrl,  _lang.t('historyType'),        Icons.build_outlined),
                const SizedBox(height: 10),
                StatefulBuilder(builder: (_, setPieces) =>
                  _PiecesMultiSelect(
                    selected: selectedPieces,
                    onChanged: () => setPieces(() {}),
                    lang: _lang,
                  )),
                const SizedBox(height: 10),
                _field(techCtrl,   _lang.t('historyTechnician'),  Icons.person_outline),
                const SizedBox(height: 10),
                _field(clientCtrl, _lang.t('historyClient'),       Icons.business_outlined),
                const SizedBox(height: 10),
                _field(descCtrl,   _lang.t('historyDescription'),  Icons.notes_outlined, maxLines: 3),
                const SizedBox(height: 12),
                // Bouton ajouter photo
                StatefulBuilder(builder: (_, setImg) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picked = await picker.pickMultiImage(imageQuality: 70);
                        for (final img in picked) {
                          final bytes = await img.readAsBytes();
                          imageBytesList.add(bytes);
                          imageNamesList.add(img.name);
                        }
                        setImg(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAB308).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.4))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.add_photo_alternate_outlined,
                            color: Color(0xFFEAB308), size: 18),
                          const SizedBox(width: 8),
                          Text(_lang.t('historyAddPhoto'), style: const TextStyle(
                            color: Color(0xFFEAB308), fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    // Photos déjà existantes (mode édition)
                    if (existingImageIds.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: existingImageIds.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _robots.getImagePreviewUrl(existingImageIds[i]),
                                width: 80, height: 80, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80, height: 80,
                                  color: Colors.white.withOpacity(0.05),
                                  child: const Icon(Icons.broken_image_outlined,
                                    color: Colors.white24, size: 20)))),
                            Positioned(top: 2, right: 2,
                              child: GestureDetector(
                                onTap: () { existingImageIds.removeAt(i); setImg(() {}); },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 14)))),
                          ]),
                        ),
                      ),
                    ],
                    // Nouvelles photos ajoutées dans cette session
                    if (imageBytesList.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageBytesList.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(imageBytesList[i],
                                width: 80, height: 80, fit: BoxFit.cover)),
                            Positioned(top: 2, right: 2,
                              child: GestureDetector(
                                onTap: () { imageBytesList.removeAt(i); imageNamesList.removeAt(i); setImg(() {}); },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 14)))),
                          ]),
                        ),
                      ),
                    ],
                  ],
                )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: StatefulBuilder(
                    builder: (_, setSaving) => ElevatedButton(
                      onPressed: saving ? null : () async {
                        if (typeCtrl.text.trim().isEmpty) return;
                        setSaving(() => saving = true);

                        if (isEdit) {
                          await _robots.updateHistoryEntry(
                            widget.doc.$id,
                            editEntry!['entryId'] as String,
                            date:        editEntry['date'] as String, // date d'origine conservée
                            type:        typeCtrl.text.trim(),
                            piece:       selectedPieces.join(', '),
                            technicien:  techCtrl.text.trim(),
                            client:      clientCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            keepImageIds:  existingImageIds,
                            newImageBytes: imageBytesList,
                            newImageNames: imageNamesList,
                          );
                        } else {
                          final now = DateTime.now();
                          final date = '${now.day.toString().padLeft(2,'0')}/'
                                       '${now.month.toString().padLeft(2,'0')}/'
                                       '${now.year}';
                          await _robots.addHistoryEntry(
                            widget.doc.$id,
                            date:        date,
                            type:        typeCtrl.text.trim(),
                            piece:       selectedPieces.join(', '),
                            technicien:  techCtrl.text.trim(),
                            client:      clientCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            imageBytes:  imageBytesList,
                            imageNames:  imageNamesList,
                          );
                        }

                        if (mounted) {
                          Navigator.pop(ctx);
                          _loadHistory();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEAB308),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                      child: saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(_lang.t('historySave'),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Suppression d'une entrée d'historique (avec confirmation) ────────────
  Future<void> _confirmDeleteEntry(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0A0A0F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline, color: Colors.red[400], size: 32),
            const SizedBox(height: 12),
            Text(_lang.t('historyDeleteConfirmTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Text(_lang.t('historyDeleteConfirmDesc'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.4)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.15)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(_lang.t('cancel'),
                  style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w700, fontSize: 13)))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0),
                child: Text(_lang.t('historyDeleteConfirmAction'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)))),
            ]),
          ]),
        ),
      ),
    );

    if (confirmed == true) {
      await _robots.deleteHistoryEntry(widget.doc.$id, entry['entryId'] as String);
      _loadHistory();
    }
  }

  // ignore: unused_element
  Widget _field(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEAB308)))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serial = widget.doc.data['serial'] as String;
    final canAdd = widget.userRole == AppRoles.superAdmin ||
                   widget.userRole == AppRoles.admin ||
                   widget.userRole == AppRoles.distributeur;

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_lang.t('historyTitle'),
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
          Text(serial, style: TextStyle(color: Colors.grey[500],
            fontSize: 10, fontFamily: 'monospace', letterSpacing: 2)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadHistory),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFEAB308)))
        : _history.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history, color: Colors.grey[700], size: 48),
              const SizedBox(height: 12),
              Text(_lang.t('historyEmpty'),
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              Text(_lang.t('historyEmptyHint'),
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final e = _history[i];
                return GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _HistoryEntryDetailDialog(entry: e, robots: _robots, lang: _lang)),
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.07))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAB308).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFEAB308).withOpacity(0.3))),
                        child: Text(e['date'] ?? '', style: const TextStyle(
                          color: Color(0xFFEAB308), fontSize: 10,
                          fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e['type'] ?? '',
                        style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 13))),
                    ]),
                    if ((e['piece'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.memory_outlined, color: Colors.grey[600], size: 13),
                        const SizedBox(width: 6),
                        Text(e['piece'] ?? '',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      ]),
                    ],
                    if ((e['technicien'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.person_outline, color: Colors.grey[600], size: 13),
                        const SizedBox(width: 6),
                        Text(e['technicien'] ?? '',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      ]),
                    ],
                    if ((e['client'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.business_outlined, color: Colors.grey[600], size: 13),
                        const SizedBox(width: 6),
                        Text(e['client'] ?? '',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      ]),
                    ],
                    if ((e['description'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(8)),
                        child: Text(e['description'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[400],
                            fontSize: 12, height: 1.5))),
                    ],
                    // Images (aperçu limité, voir détail pour tout afficher)
                    if ((e['images'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: Row(children: [
                          ...List.generate(
                            (e['images'] as List).length > 4 ? 3 : (e['images'] as List).length,
                            (i) {
                              final fileId = (e['images'] as List)[i] as String;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(_robots.getImagePreviewUrl(fileId),
                                    width: 56, height: 56, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 56, height: 56,
                                      color: Colors.white.withOpacity(0.05),
                                      child: const Icon(Icons.broken_image_outlined,
                                        color: Colors.white24, size: 20)))));
                            }),
                          if ((e['images'] as List).length > 4)
                            Container(
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAB308).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.3))),
                              child: Center(child: Text(
                                '+${(e['images'] as List).length - 3}',
                                style: const TextStyle(color: Color(0xFFEAB308),
                                  fontWeight: FontWeight.w900, fontSize: 13)))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      GestureDetector(
                        onTap: () => _showAddEntry(editEntry: e),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.edit_outlined, color: Colors.grey[400], size: 15)),
                      ),
                      GestureDetector(
                        onTap: () => _confirmDeleteEntry(e),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.delete_outline, color: Colors.red[300], size: 15)),
                      ),
                    ]),
                  ]),
                  ),
                );
              }),
      floatingActionButton: canAdd
        ? FloatingActionButton(
            onPressed: _showAddEntry,
            backgroundColor: const Color(0xFFEAB308),
            foregroundColor: Colors.black,
            child: const Icon(Icons.add))
        : null,
    );
  }
}

// ══════════════════════════════════════════════════
// RÉFÉRENCES PIÈCES BZLIGHT
// ══════════════════════════════════════════════════
const List<String> _allBzlParts = [
  'BZL-011', 'BZL-012', 'BZL-013', 'BZL-100', 'BZL-101', 'BZL-102',
  'BZL-103', 'BZL-104', 'BZL-105', 'BZL-106', 'BZL-107', 'BZL-117',
  'ROCOL-SAPPHIRE', 'BZL-021-A', 'BZL-021-B', 'BZL-201', 'BZL-202',
  'BZL-203', 'BZL-204', 'BZL-206', 'BZL-031A', 'BZL-300', 'BZL-301',
  'BZL-302', 'BZL-303', 'BZL-304', 'BZL-305', 'BZL-306', 'BZL-307',
  'BZL-308', 'BZL-309', 'BZL-310', 'BZL-311', 'BZL-312', 'BZL-313',
  'BZL-314', 'BZL-315', 'BZL-AC-104', 'BZL-AC-105', 'FIJ-ORN-3x1',
  'FIJ-ORN-3.5x1', 'FIJ-ORN-16x1.5', 'FIJ-ORN-28x1.5', 'FIJ-ORS-18x2',
  'FIT-RBS-626-2RS-I', 'FIV-BHC-M6-25-Z', 'FIV-CHC-M2-06-B',
  'FIV-FTO-M3-08-Z', 'FIV-FTO-M3-10-Z', 'FIV-ROG-06-I',
  'FTR-CRAV-160VS EM14', 'HPS-08E-124',
];

// ══════════════════════════════════════════════════
// DIALOG DÉTAIL D'UNE FICHE D'HISTORIQUE
// ══════════════════════════════════════════════════
class _HistoryEntryDetailDialog extends StatelessWidget {
  final Map<String, dynamic> entry;
  final RobotService robots;
  final LangService lang;
  const _HistoryEntryDetailDialog({required this.entry, required this.robots, required this.lang});

  Widget _row(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFFEAB308).withOpacity(0.7), size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = (entry['images'] as List?)?.cast<String>() ?? [];
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(entry['date'] ?? '', style: const TextStyle(
                  color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900))),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: Colors.grey[600], size: 22)),
            ]),
            const SizedBox(height: 16),
            Text(entry['type'] ?? '', style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 18),
            _row(Icons.memory_outlined, 'PIÈCE(S) CONCERNÉE(S)', entry['piece'] ?? ''),
            _row(Icons.person_outline, 'TECHNICIEN', entry['technicien'] ?? ''),
            _row(Icons.business_outlined, 'CLIENT', entry['client'] ?? ''),
            if ((entry['description'] as String? ?? '').isNotEmpty) ...[
              Text('DESCRIPTION', style: TextStyle(color: Colors.grey[600], fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(10)),
                child: Text(entry['description'] ?? '',
                  style: TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.6))),
              const SizedBox(height: 18),
            ],
            if (images.isNotEmpty) ...[
              Text('PHOTOS (${images.length})', style: TextStyle(color: Colors.grey[600],
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: images.length,
                itemBuilder: (_, i) {
                  final fileId = images[i];
                  final previewUrl = robots.getImagePreviewUrl(fileId);
                  final viewUrl    = robots.getImageViewUrl(fileId);
                  return GestureDetector(
                    onTap: () => showDialog(context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: const EdgeInsets.all(16),
                        child: InteractiveViewer(
                          child: Image.network(viewUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator(
                                  color: Color(0xFFEAB308))))))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(previewUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              color: Colors.white.withOpacity(0.05),
                              child: const Center(child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFEAB308))))),
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.white.withOpacity(0.05),
                          child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white24, size: 24)))));
                }),
            ],
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// SÉLECTEUR MULTI-PIÈCES (inline, sans Overlay)
// ══════════════════════════════════════════════════
class _PiecesMultiSelect extends StatefulWidget {
  final List<String> selected;
  final VoidCallback onChanged;
  final LangService lang;
  const _PiecesMultiSelect({required this.selected, required this.onChanged, required this.lang});
  @override
  State<_PiecesMultiSelect> createState() => _PiecesMultiSelectState();
}

class _PiecesMultiSelectState extends State<_PiecesMultiSelect> {
  final _searchCtrl = TextEditingController();
  final _focusNode  = FocusNode();
  List<String> _filtered = List.from(_allBzlParts);
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted) setState(() => _open = false);
    });
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_allBzlParts)
          : _allBzlParts.where((p) => p.toUpperCase().contains(q)).toList();
    });
  }

  void _addPart(String part) {
    if (!widget.selected.contains(part)) {
      widget.selected.add(part);
      widget.onChanged();
    }
    _searchCtrl.clear();
    setState(() => _open = false);
    _focusNode.unfocus();
  }

  void _addManual() {
    final val = _searchCtrl.text.trim();
    if (val.isNotEmpty && !widget.selected.contains(val)) {
      widget.selected.add(val);
      widget.onChanged();
    }
    _searchCtrl.clear();
    setState(() => _open = false);
    _focusNode.unfocus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Chips des pièces sélectionnées ──────────────────────────────
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.selected.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEAB308).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.memory_outlined, color: Color(0xFFEAB308), size: 12),
                const SizedBox(width: 5),
                Text(p, style: const TextStyle(
                  color: Color(0xFFEAB308), fontSize: 12,
                  fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    widget.selected.remove(p);
                    widget.onChanged();
                    setState(() {});
                  },
                  child: const Icon(Icons.close, color: Color(0xFFEAB308), size: 13)),
              ]),
            )).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // ── Champ de recherche ───────────────────────────────────────────
        TextField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          onTap: () => setState(() => _open = true),
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: widget.lang.t('historyPiece'),
            labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
            prefixIcon: Icon(Icons.memory_outlined, color: Colors.grey[600], size: 18),
            suffixIcon: _open
                ? Icon(Icons.keyboard_arrow_up,
                    color: const Color(0xFFEAB308).withOpacity(0.7), size: 20)
                : Icon(Icons.keyboard_arrow_down,
                    color: Colors.grey[600], size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            hintText: 'Chercher ou saisir librement…',
            hintStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFEAB308))),
          ),
        ),

        // ── Dropdown inline ──────────────────────────────────────────────
        if (_open) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFF12121A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.35)),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                // Saisie manuelle si texte non vide et pas dans la liste
                if (_searchCtrl.text.trim().isNotEmpty &&
                    !_allBzlParts.any((p) => p.toUpperCase() ==
                        _searchCtrl.text.trim().toUpperCase()))
                  InkWell(
                    onTap: _addManual,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Icon(Icons.add_circle_outline,
                            color: Colors.grey[500], size: 14),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          'Ajouter "${_searchCtrl.text.trim()}"',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12))),
                      ]),
                    ),
                  ),
                // Résultats filtrés
                ..._filtered.map((part) => InkWell(
                  onTap: () => _addPart(part),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.memory_outlined,
                          color: widget.selected.contains(part)
                              ? const Color(0xFFEAB308)
                              : const Color(0xFFEAB308).withOpacity(0.5),
                          size: 14),
                      const SizedBox(width: 10),
                      Expanded(child: Text(part,
                          style: TextStyle(
                              color: widget.selected.contains(part)
                                  ? const Color(0xFFEAB308)
                                  : Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: widget.selected.contains(part)
                                  ? FontWeight.w700
                                  : FontWeight.normal))),
                      if (widget.selected.contains(part))
                        const Icon(Icons.check, color: Color(0xFFEAB308), size: 14),
                    ]),
                  ),
                )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
