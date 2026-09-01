// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';
import '../services/auth_service.dart';
import '../services/lang_service.dart';
import 'pump_detail_screen.dart';

/// Carte d'ensemble des pompes — affiche TOUTES les positions
/// historiques enregistrées (pas juste la plus récente). Si une pompe
/// est passée par 10 endroits différents, les 10 marqueurs apparaissent
/// tous, chacun tapable pour voir la date exacte et accéder au détail
/// de la pompe concernée.
class PumpMapScreen extends StatefulWidget {
  const PumpMapScreen({super.key});
  @override
  State<PumpMapScreen> createState() => _PumpMapScreenState();
}

class _PumpMapScreenState extends State<PumpMapScreen> {
  final _service = PumpService();
  final _auth = AuthService();
  final _lang = LangService();
  List<models.Document> _locations = [];
  Map<String, String> _pumpNames = {}; // pumpId -> name, pour l'affichage
  bool _loading = true;

  static const List<Color> _pumpColors = [
    Color(0xFF22D3EE), Colors.amber, Colors.purpleAccent,
    Colors.greenAccent, Colors.redAccent, Colors.orangeAccent,
  ];

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
      print('[PumpMapScreen] Erreur récupération entreprise/rôle : $e');
    }
    final locations = await _service.getAllPumpLocations(company: company, role: role);
    final pumps = await _service.listPumps(company: company, role: role);
    if (mounted) {
      setState(() {
        _locations = locations;
        _pumpNames = {for (final p in pumps) p.$id: p.data['name'] as String? ?? p.$id};
        _loading = false;
      });
    }
  }

  Color _colorForPump(String pumpId) {
    final ids = _pumpNames.keys.toList();
    final index = ids.indexOf(pumpId);
    if (index == -1) return _pumpColors.first;
    return _pumpColors[index % _pumpColors.length];
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
           '${d.month.toString().padLeft(2, '0')}/${d.year} '
           '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _showLocationInfo(models.Document loc) {
    final pumpId = loc.data['pumpId'] as String;
    final name = _pumpNames[pumpId] ?? pumpId;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 12, height: 12,
              decoration: BoxDecoration(
                color: _colorForPump(pumpId), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.schedule, color: Colors.grey[500], size: 14),
            const SizedBox(width: 6),
            Text(_formatDate(loc.data['capturedAt'] as String?),
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PumpDetailScreen(pumpId: pumpId, pumpName: name)));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(_lang.t('pumpMapViewPumpBtn'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validLocations = _locations.where((l) =>
      l.data['lat'] != null && l.data['lng'] != null).toList();

    final center = validLocations.isNotEmpty
      ? latlong.LatLng(
          (validLocations.first.data['lat'] as num).toDouble(),
          (validLocations.first.data['lng'] as num).toDouble())
      : latlong.LatLng(46.6, 2.2); // France, vue par défaut si aucune position

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(_lang.t('pumpMapTitle'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _load),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
        : validLocations.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.map_outlined, color: Colors.grey[700], size: 56),
                const SizedBox(height: 16),
                Text(_lang.t('pumpMapEmptyTitle'),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 16),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_lang.t('pumpMapEmptySubtitle'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  textAlign: TextAlign.center),
              ])))
          : FlutterMap(
              options: MapOptions(center: center, zoom: 6),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bzbotsapp',
                ),
                MarkerLayer(
                  markers: validLocations.map<Marker>((loc) {
                    final pumpId = loc.data['pumpId'] as String;
                    return Marker(
                      point: latlong.LatLng(
                        (loc.data['lat'] as num).toDouble(),
                        (loc.data['lng'] as num).toDouble()),
                      width: 36, height: 36,
                      builder: (context) => GestureDetector(
                        onTap: () => _showLocationInfo(loc),
                        child: Icon(Icons.location_on,
                          color: _colorForPump(pumpId), size: 36)),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}
