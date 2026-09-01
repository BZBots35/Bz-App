// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';
import '../services/auth_service.dart';
import '../services/lang_service.dart';
import 'pump_detail_screen.dart';
import 'pump_fake_data.dart';

/// Liste des pompes connues — une pompe apparaît ici dès qu'on s'est
/// connecté au moins une fois à sa Pi (découverte automatique, voir
/// PumpService.getOrCreatePump, déclenchée depuis pump_control_screen).
/// Fonctionne dès aujourd'hui avec une seule pompe, prêt à en afficher
/// plusieurs sans rien changer le jour où d'autres sont mises en service.
class PumpListScreen extends StatefulWidget {
  const PumpListScreen({super.key});
  @override
  State<PumpListScreen> createState() => _PumpListScreenState();
}

class _PumpListScreenState extends State<PumpListScreen> {
  final _service = PumpService();
  final _auth = AuthService();
  final _lang = LangService();
  List<models.Document> _pumps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String company = '';
    String role = '';
    try {
      final user = await _auth.getCurrentUser();
      if (user != null) {
        company = await _auth.getUserCompany(user.$id);
        role = await _auth.getUserRole(user.$id);
      }
    } catch (e) {
      print('[PumpListScreen] Erreur récupération entreprise/rôle : $e');
    }
    final list = await _service.listPumps(company: company, role: role);
    if (mounted) setState(() { _pumps = list; _loading = false; });
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m}min';
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
        title: Text(_lang.t('pumpListTitle'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _load),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : _pumps.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.water_drop_outlined,
                  color: Colors.grey[700], size: 56),
                const SizedBox(height: 16),
                Text(_lang.t('pumpListEmptyTitle'),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 16),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_lang.t('pumpListEmptySubtitle'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  textAlign: TextAlign.center),
              ])))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF22D3EE),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pumps.length,
                itemBuilder: (_, i) => _pumpCard(_pumps[i]),
              ),
            ),
    );
  }

  Widget _pumpCard(models.Document pump) {
    final name = pump.data['name'] as String? ?? pump.$id;
    final totalSeconds = PumpFakeData.enabled
      ? PumpFakeData.totalSeconds()
      : (pump.data['totalRuntimeSeconds'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PumpDetailScreen(pumpId: pump.$id, pumpName: name)))
        .then((_) => _load()), // rafraîchit si le nom a été modifié
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2))),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.3))),
            child: const Icon(Icons.water_drop,
              color: Color(0xFF22D3EE), size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.schedule, color: Colors.grey[600], size: 12),
              const SizedBox(width: 4),
              Text('${_lang.t('pumpListTotalTimePrefix')} ${_formatDuration(totalSeconds)}',
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ]),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey[600], size: 20),
        ]),
      ),
    );
  }
}
