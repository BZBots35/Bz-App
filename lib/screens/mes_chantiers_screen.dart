// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appwrite/models.dart' as models;
import '../services/bzvision_service.dart';
import '../widgets/lang_selector.dart';
import 'bzvision_chantier_screen.dart';
import '../services/pump_service.dart';
import 'pump_chantier_screen.dart';

enum ChantierModule { bzvision, pompe, bzlight }

class ChantierUnifie {
  final String id;
  final String nom;
  final String adresse;
  final String date;
  final ChantierModule module;
  final String statut;
  final int nbCanalisations;
  final int nbInspectees;
  double? lat;
  double? lng;
  final dynamic rawDoc;

  ChantierUnifie({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.date,
    required this.module,
    required this.statut,
    required this.nbCanalisations,
    required this.nbInspectees,
    this.lat,
    this.lng,
    this.rawDoc,
  });
}

class MesChantierScreen extends StatefulWidget {
  final String userRole;
  final String userId;
  final String userName;

  const MesChantierScreen({
    super.key,
    required this.userRole,
    required this.userId,
    required this.userName,
  });

  @override
  State<MesChantierScreen> createState() => _MesChantierScreenState();
}

class _MesChantierScreenState extends State<MesChantierScreen> {
  final _service       = BzVisionService();
  final _mapController = MapController();
  final _searchCtrl    = TextEditingController();

  List<ChantierUnifie> _chantiers   = [];
  List<ChantierUnifie> _filtered    = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading        = true;
  bool _showSuggestions = false;
  String _searchQuery  = '';

  Map<String, Map<String, double>> _gpsCache = {};
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _loadGpsCache();
    _loadChantiers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGpsCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('gps_cache_chantiers');
    if (raw != null) {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _gpsCache = decoded.map((k, v) =>
        MapEntry(k, Map<String, double>.from(v)));
    }
  }

  Future<void> _saveGpsCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gps_cache_chantiers', json.encode(_gpsCache));
  }

  Future<void> _loadChantiers() async {
    setState(() => _loading = true);
    try {
      final docs = await _service.getChantiers(
        widget.userId, widget.userRole);

      final List<ChantierUnifie> result = [];
      for (final doc in docs) {
        final d          = doc.data;
        final canalisations = await _service.getCanalisations(doc.$id);
        final nbInsp     = canalisations
          .where((c) => c.data['statut'] == 'inspecte').length;
        final adresse    = d['adresse'] as String? ?? '';

        double? lat, lng;
        if (adresse.isNotEmpty) {
          final cached = _gpsCache[adresse];
          if (cached != null) {
            lat = cached['lat'];
            lng = cached['lng'];
          } else {
            final coords = await _geocode(adresse);
            if (coords != null) {
              lat = coords['lat'];
              lng = coords['lng'];
              _gpsCache[adresse] = {'lat': lat!, 'lng': lng!};
              await _saveGpsCache();
            }
          }
        }

        result.add(ChantierUnifie(
          id:              doc.$id,
          nom:             d['nom']    as String? ?? 'Chantier sans nom',
          adresse:         adresse,
          date:            d['date']   as String? ?? '',
          module:          ChantierModule.bzvision,
          statut:          d['statut'] as String? ?? '',
          nbCanalisations: canalisations.length,
          nbInspectees:    nbInsp,
          lat: lat,
          lng: lng,
          rawDoc: doc,
        ));
        _cardKeys[doc.$id] = GlobalKey();
      }

      if (mounted) setState(() {
        _chantiers = result;
        _filtered  = result;
        _loading   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, double>?> _geocode(String adresse) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&q=${Uri.encodeComponent(adresse)}&limit=1');
      final resp = await http.get(uri,
        headers: {'User-Agent': 'BZBots-App/1.0'})
        .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as List;
        if (data.isNotEmpty) {
          return {
            'lat': double.parse(data[0]['lat']),
            'lng': double.parse(data[0]['lon']),
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _onSearchChanged(String val) async {
    _filterChantiers(val);
    if (val.length < 3) {
      setState(() { _showSuggestions = false; _suggestions = []; });
      return;
    }
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&q=${Uri.encodeComponent(val)}&limit=5&addressdetails=1');
      final resp = await http.get(uri,
        headers: {'User-Agent': 'BZBots-App/1.0', 'Accept-Language': 'fr'})
        .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body) as List;
        setState(() {
          _suggestions    = data.cast<Map<String, dynamic>>();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  void _selectSuggestion(Map<String, dynamic> s) {
    final lat = double.tryParse(s['lat'].toString());
    final lng = double.tryParse(s['lon'].toString());
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 14);
    }
    _searchCtrl.text = s['display_name'] ?? '';
    setState(() { _showSuggestions = false; _suggestions = []; });
  }

  void _filterChantiers(String query) {
    setState(() {
      _searchQuery = query;
      _filtered = _chantiers.where((c) {
        final q = query.toLowerCase();
        return c.nom.toLowerCase().contains(q) ||
               c.adresse.toLowerCase().contains(q);
      }).toList();
    });
  }

  Color _moduleColor(ChantierModule m) => switch (m) {
    ChantierModule.bzvision => const Color(0xFF22D3EE),
    ChantierModule.pompe    => const Color(0xFFA855F7),
    ChantierModule.bzlight  => const Color(0xFFEAB308),
  };

  String _moduleLabel(ChantierModule m) => switch (m) {
    ChantierModule.bzvision => 'BzVision',
    ChantierModule.pompe    => 'Pompe',
    ChantierModule.bzlight  => 'BzLight',
  };

  IconData _moduleIcon(ChantierModule m) => switch (m) {
    ChantierModule.bzvision => Icons.videocam_outlined,
    ChantierModule.pompe    => Icons.science_outlined,
    ChantierModule.bzlight  => Icons.bolt_outlined,
  };

  String _statutLabel(String s) => switch (s) {
    'termine'  => 'Terminé',
    'en_cours' => 'En cours',
    _          => 'Ouvert',
  };

  Color _statutColor(String s) => switch (s) {
    'termine'  => Colors.green,
    'en_cours' => const Color(0xFF22D3EE),
    _          => Colors.grey,
  };

  void _fitMapBounds() {
    final points = _chantiers
      .where((c) => c.lat != null && c.lng != null)
      .map((c) => LatLng(c.lat!, c.lng!))
      .toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 13);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitBounds(bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(40)));
  }

  void _openChantier(ChantierUnifie c) {
    if (c.module == ChantierModule.bzvision && c.rawDoc != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => BzVisionChantierScreen(
          chantierDoc: c.rawDoc as models.Document,
          userRole:    widget.userRole,
          userId:      widget.userId,
          userName:    widget.userName,
        ),
      )).then((_) => _loadChantiers());
    }
  }

  void _onMarkerTap(ChantierUnifie c) {
    _mapController.move(LatLng(c.lat!, c.lng!), 15);
    final key = _cardKeys[c.id];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut);
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
        title: const Text('MES CHANTIERS',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh,
              color: Color(0xFF22D3EE), size: 20),
            onPressed: _loadChantiers),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : Column(children: [
            _buildMap(),
            Expanded(child: _buildList()),
          ]),
    );
  }

  Widget _buildMap() {
    // Construction des marqueurs v4
    final List<Marker> markers = _chantiers
      .where((c) => c.lat != null && c.lng != null)
      .map((c) => Marker(
        point:  LatLng(c.lat!, c.lng!),
        width:  40,
        height: 40,
        builder: (ctx) => GestureDetector(
          onTap: () => _onMarkerTap(c),
          child: Container(
            decoration: BoxDecoration(
              color: _moduleColor(c.module).withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: _moduleColor(c.module).withOpacity(0.5),
                blurRadius: 10, spreadRadius: 2)]),
            child: Icon(_moduleIcon(c.module),
              color: Colors.black, size: 18)),
        ),
      )).toList();

    return Container(
      height: 250,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(
          color: Colors.white.withOpacity(0.08)))),
      child: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: LatLng(46.8, 2.3),
            zoom:   5,
            onMapReady: () => Future.delayed(
              const Duration(milliseconds: 300), _fitMapBounds)),
          children: [
            TileLayer(
              urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bzbots.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Bouton recadrer
        Positioned(bottom: 10, right: 10,
          child: GestureDetector(
            onTap: _fitMapBounds,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15))),
              child: const Icon(Icons.fit_screen,
                color: Colors.white70, size: 18)))),
        // Légende
        Positioned(bottom: 10, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              _legendDot(const Color(0xFF22D3EE), 'BzVision'),
              const SizedBox(width: 10),
              _legendDot(const Color(0xFFA855F7), 'Pompe'),
              const SizedBox(width: 10),
              _legendDot(const Color(0xFFEAB308), 'BzLight'),
            ]))),
      ]),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 8, height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: Colors.white70,
      fontSize: 9, fontWeight: FontWeight.w700)),
  ]);

  Widget _buildList() {
    return Column(children: [
      _buildSearchBar(),
      Expanded(child: _filtered.isEmpty
        ? _buildEmpty()
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _filtered.length,
            itemBuilder: (_, i) => _buildCard(_filtered[i]))),
    ]);
  }

  Widget _buildSearchBar() {
    return Container(
      color: const Color(0xFF0A0A0F),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1))),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher un chantier ou une adresse...',
                hintStyle: TextStyle(
                  color: Colors.grey[700], fontSize: 12),
                prefixIcon: const Icon(Icons.search,
                  color: Color(0xFF22D3EE), size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close,
                        color: Colors.grey[600], size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        _filterChantiers('');
                        setState(() => _showSuggestions = false);
                      })
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12)),
            ),
          ),
        ),
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1))),
            child: Column(
              children: _suggestions.take(5).map((s) {
                final name = s['display_name'] as String? ?? '';
                return InkWell(
                  onTap: () => _selectSuggestion(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.place_outlined,
                        color: Color(0xFF22D3EE), size: 14),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        name.length > 60
                          ? '${name.substring(0, 57)}...' : name,
                        style: const TextStyle(color: Colors.white70,
                          fontSize: 11, fontWeight: FontWeight.w600))),
                    ])));
              }).toList(),
            ),
          ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('${_filtered.length} chantier${_filtered.length > 1 ? 's' : ''}',
              style: TextStyle(color: Colors.grey[600],
                fontSize: 10, fontWeight: FontWeight.w700)),
            const Spacer(),
            ...[ChantierModule.bzvision, ChantierModule.pompe,
                ChantierModule.bzlight].map((m) {
              final count = _filtered
                .where((c) => c.module == m).length;
              if (count == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _moduleColor(m).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _moduleColor(m).withOpacity(0.3))),
                child: Text('$count ${_moduleLabel(m)}',
                  style: TextStyle(color: _moduleColor(m),
                    fontSize: 9, fontWeight: FontWeight.w900)));
            }),
          ])),
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.white.withOpacity(0.06)),
      ]),
    );
  }

  Widget _buildCard(ChantierUnifie c) {
    final color  = _moduleColor(c.module);
    final hasGps = c.lat != null && c.lng != null;

    return Container(
      key: _cardKeys[c.id],
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: color.withOpacity(0.5), width: 3)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.3), blurRadius: 10)]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3))),
              child: Icon(_moduleIcon(c.module), color: color, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.nom, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.3))),
                  child: Text(_moduleLabel(c.module),
                    style: TextStyle(color: color,
                      fontSize: 9, fontWeight: FontWeight.w900))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statutColor(c.statut).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _statutColor(c.statut).withOpacity(0.3))),
                  child: Text(_statutLabel(c.statut),
                    style: TextStyle(color: _statutColor(c.statut),
                      fontSize: 9, fontWeight: FontWeight.w900))),
              ]),
            ])),
            if (hasGps)
              GestureDetector(
                onTap: () => _onMarkerTap(c),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3))),
                  child: const Icon(Icons.map_outlined,
                    color: Colors.blue, size: 16))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(children: [
            if (c.adresse.isNotEmpty)
              Row(children: [
                Icon(Icons.place_outlined,
                  color: Colors.grey[600], size: 12),
                const SizedBox(width: 6),
                Expanded(child: Text(c.adresse,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            if (c.date.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.calendar_today_outlined,
                  color: Colors.grey[600], size: 12),
                const SizedBox(width: 6),
                Text(c.date, style: TextStyle(
                  color: Colors.grey[500], fontSize: 11)),
              ]),
            ],
            if (c.nbCanalisations > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                _statBadge('${c.nbCanalisations}',
                  'canalisation${c.nbCanalisations > 1 ? 's' : ''}',
                  Colors.white24),
                const SizedBox(width: 8),
                _statBadge('${c.nbInspectees}',
                  'inspectée${c.nbInspectees > 1 ? 's' : ''}',
                  Colors.green.withOpacity(0.2)),
              ]),
            ],
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16))),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16)),
              onTap: () => _openChantier(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                  Text('OUVRIR LE CHANTIER',
                    style: TextStyle(color: color,
                      fontSize: 10, fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
                  Icon(Icons.arrow_forward_ios, color: color, size: 12),
                ])))),
        ),
      ]),
    );
  }

  Widget _statBadge(String value, String label, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: const TextStyle(color: Colors.white,
        fontSize: 11, fontWeight: FontWeight.w900)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
    ]));

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.folder_open_outlined,
        color: Colors.grey[700], size: 48),
      const SizedBox(height: 12),
      Text(_searchQuery.isNotEmpty
        ? 'Aucun résultat pour "$_searchQuery"'
        : 'Aucun chantier disponible',
        style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      const SizedBox(height: 4),
      Text('Créez un chantier depuis BzVision',
        style: TextStyle(color: Colors.grey[700], fontSize: 11)),
    ]));
}
