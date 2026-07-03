// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../widgets/lang_selector.dart';
import 'pump_chantier_screen.dart';
import 'pump_rapports_screen.dart';

class PumpScreen extends StatefulWidget {
  const PumpScreen({super.key});
  @override
  State<PumpScreen> createState() => _PumpScreenState();
}

class _PumpScreenState extends State<PumpScreen> {
  final _service = PumpService();
  final _auth    = AuthService();
  List<models.Document> _chantiers = [];
  bool   _loading  = true;
  String _userId   = '';
  String _userName = '';
  String _userRole = 'client';
  String _company  = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final user = await _auth.getCurrentUser();
    if (user != null) {
      final role    = await _auth.getUserRole(user.$id);
      final company = await _auth.getUserCompany(user.$id);
      final list    = await _service.getChantiers(user.$id, role);
      if (mounted) setState(() {
        _userId   = user.$id;
        _userName = user.name;
        _userRole = role;
        _company  = company;
        _chantiers = list;
        _loading  = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _showCreateChantier() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateChantierSheet(),
    );
    if (result != null) {
      await _service.createChantier(
        nom:          result['nom'],
        ville:        result['ville'],
        rue:          result['rue'],
        batiment:     result['batiment'],
        date:         result['date'],
        userId:       _userId,
        company:      _company,
        resinType:    'spraycoat_plus',
        epaisseur:    '0.75',
        desiredPasses: 4,
      );
      _loadData();
    }
  }

  Future<void> _deleteChantier(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Supprimer ?',
          style: TextStyle(color: Colors.white)),
        content: const Text('Ce chantier sera supprimé définitivement.',
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
              style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer',
              style: TextStyle(color: Colors.red))),
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
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF22D3EE).withOpacity(0.3))),
            child: const Icon(Icons.water_drop,
              color: Color(0xFF22D3EE), size: 14)),
          const SizedBox(width: 8),
          const Text('POMPE RÉSINE',
            style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 14,
              letterSpacing: 1.5)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined,
              color: Color(0xFF22D3EE), size: 20),
            tooltip: 'Tous les rapports',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PumpRapportsScreen()))),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadData),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : Column(children: [
            _buildStats(),
            Expanded(
              child: _chantiers.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: const Color(0xFF22D3EE),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _chantiers.length,
                      itemBuilder: (_, i) =>
                        _buildChantierCard(_chantiers[i]),
                    ),
                  ),
            ),
          ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateChantier,
        backgroundColor: const Color(0xFF22D3EE),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Créer chantier',
          style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildStats() {
    final total = _chantiers.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(bottom: BorderSide(
          color: Colors.white.withOpacity(0.06)))),
      child: Row(children: [
        _statBox('Chantiers', '$total', const Color(0xFF22D3EE)),
        const SizedBox(width: 12),
        _statBox('Résine', 'A/B', Colors.purple),
        const SizedBox(width: 12),
        _statBox('Wi-Fi', 'Ready', Colors.green),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(color: color,
          fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: TextStyle(color: color.withOpacity(0.7),
          fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
    ));
  }

  Widget _buildEmpty() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF22D3EE).withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF22D3EE).withOpacity(0.2))),
        child: Icon(Icons.water_drop_outlined,
          color: const Color(0xFF22D3EE).withOpacity(0.5), size: 36)),
      const SizedBox(height: 20),
      const Text('Aucun chantier', style: TextStyle(color: Colors.white,
        fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      Text('Appuyez sur + pour créer votre premier chantier',
        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      const SizedBox(height: 80),
    ]));
  }

  Future<void> _showEditChantier(models.Document doc) async {
    final d = doc.data;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditChantierSheet(chantierDoc: doc),
    );
    if (result != null) {
      await _service.updateChantier(doc.$id,
        nom:      result['nom'],
        ville:    result['ville'],
        rue:      result['rue'],
        batiment: result['batiment'],
        date:     result['date'],
      );
      _loadData();
    }
  }

  Widget _buildChantierCard(models.Document doc) {
    final d   = doc.data;
    final nom = d['nom']  as String? ?? '';
    final vil = d['ville'] as String? ?? '';
    final rue = d['rue']   as String? ?? '';
    final dat = d['date']  as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PumpChantierScreen(
          chantierDoc: doc,
          userId:      _userId,
          userName:    _userName,
          userRole:    _userRole,
        ))).then((_) => _loadData()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF22D3EE).withOpacity(0.2)),
          boxShadow: [BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.05),
            blurRadius: 12)]),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF22D3EE).withOpacity(0.3))),
            child: const Icon(Icons.water_drop,
              color: Color(0xFF22D3EE), size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.location_on_outlined,
                color: Colors.grey[600], size: 11),
              const SizedBox(width: 3),
              Expanded(child: Text('$rue, $vil',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                overflow: TextOverflow.ellipsis)),
            ]),
            Row(children: [
              Icon(Icons.calendar_today_outlined,
                color: Colors.grey[700], size: 11),
              const SizedBox(width: 3),
              Text(dat, style: TextStyle(
                color: Colors.grey[700], fontSize: 10)),
            ]),
          ])),
          Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.chevron_right,
                color: Color(0xFF22D3EE), size: 18)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showEditChantier(doc),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.edit_outlined,
                  color: Colors.orange[400], size: 14))),
            if (_userRole == AppRoles.superAdmin ||
                _userRole == AppRoles.admin) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _deleteChantier(doc.$id),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.delete_outline,
                    color: Colors.red[400], size: 14))),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ── Modal création chantier ───────────────────────
class _CreateChantierSheet extends StatefulWidget {
  const _CreateChantierSheet();
  @override
  State<_CreateChantierSheet> createState() => _CreateChantierSheetState();
}

class _CreateChantierSheetState extends State<_CreateChantierSheet> {
  final _nomCtrl  = TextEditingController();
  final _vilCtrl  = TextEditingController();
  final _rueCtrl  = TextEditingController();
  final _batCtrl  = TextEditingController();
  DateTime _date  = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('NOUVEAU CHANTIER', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900,
            fontSize: 13, letterSpacing: 2)),
          const SizedBox(height: 20),
          // Date
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: (_, child) => Theme(
                  data: ThemeData.dark(), child: child!));
              if (d != null) setState(() => _date = d);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08))),
              child: Row(children: [
                Icon(Icons.calendar_today,
                  color: Colors.grey[500], size: 16),
                const SizedBox(width: 10),
                Text(
                  '${_date.day.toString().padLeft(2,'0')}/'
                  '${_date.month.toString().padLeft(2,'0')}/'
                  '${_date.year}',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 13)),
              ])),
          ),
          const SizedBox(height: 10),
          _field(_nomCtrl, 'Nom du chantier *',
            Icons.construction_outlined),
          const SizedBox(height: 10),
          _field(_vilCtrl, 'Ville', Icons.location_city_outlined),
          const SizedBox(height: 10),
          _field(_rueCtrl, 'Rue', Icons.map_outlined),
          const SizedBox(height: 10),
          _field(_batCtrl, 'N° bâtiment', Icons.apartment_outlined),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_nomCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'nom':      _nomCtrl.text.trim(),
                  'ville':    _vilCtrl.text.trim(),
                  'rue':      _rueCtrl.text.trim(),
                  'batiment': _batCtrl.text.trim(),
                  'date': '${_date.day.toString().padLeft(2,'0')}/'
                          '${_date.month.toString().padLeft(2,'0')}/'
                          '${_date.year}',
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('CRÉER', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13,
                letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 16),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}

// ── Modal édition chantier ───────────────────────
class _EditChantierSheet extends StatefulWidget {
  final models.Document chantierDoc;
  const _EditChantierSheet({required this.chantierDoc});
  @override
  State<_EditChantierSheet> createState() => _EditChantierSheetState();
}

class _EditChantierSheetState extends State<_EditChantierSheet> {
  late TextEditingController _nomCtrl;
  late TextEditingController _vilCtrl;
  late TextEditingController _rueCtrl;
  late TextEditingController _batCtrl;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final d = widget.chantierDoc.data;
    _nomCtrl = TextEditingController(text: d['nom'] as String? ?? '');
    _vilCtrl = TextEditingController(text: d['ville'] as String? ?? '');
    _rueCtrl = TextEditingController(text: d['rue'] as String? ?? '');
    _batCtrl = TextEditingController(text: d['batiment'] as String? ?? '');
    // Parser la date existante
    final dateStr = d['date'] as String? ?? '';
    try {
      final parts = dateStr.split('/');
      _date = DateTime(int.parse(parts[2]),
        int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {
      _date = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('MODIFIER LE CHANTIER', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900,
            fontSize: 13, letterSpacing: 2)),
          const SizedBox(height: 20),
          // Date
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: (_, child) => Theme(
                  data: ThemeData.dark(), child: child!));
              if (d != null) setState(() => _date = d);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08))),
              child: Row(children: [
                Icon(Icons.calendar_today,
                  color: Colors.grey[500], size: 16),
                const SizedBox(width: 10),
                Text(
                  '${_date.day.toString().padLeft(2,'0')}/'
                  '${_date.month.toString().padLeft(2,'0')}/'
                  '${_date.year}',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 13)),
              ])),
          ),
          const SizedBox(height: 10),
          _field(_nomCtrl, 'Nom du chantier *',
            Icons.construction_outlined),
          const SizedBox(height: 10),
          _field(_vilCtrl, 'Ville', Icons.location_city_outlined),
          const SizedBox(height: 10),
          _field(_rueCtrl, 'Rue', Icons.map_outlined),
          const SizedBox(height: 10),
          _field(_batCtrl, 'N° bâtiment', Icons.apartment_outlined),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_nomCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'nom':      _nomCtrl.text.trim(),
                  'ville':    _vilCtrl.text.trim(),
                  'rue':      _rueCtrl.text.trim(),
                  'batiment': _batCtrl.text.trim(),
                  'date': '${_date.day.toString().padLeft(2,'0')}/'
                          '${_date.month.toString().padLeft(2,'0')}/'
                          '${_date.year}',
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('ENREGISTRER', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13,
                letterSpacing: 2)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 16),
        filled: true, fillColor: Colors.black.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}
