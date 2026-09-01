// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import '../services/pump_service.dart';
import '../services/lang_service.dart';
import 'pump_fake_data.dart';

class PumpDetailScreen extends StatefulWidget {
  final String pumpId;
  final String pumpName;
  const PumpDetailScreen({
    super.key, required this.pumpId, required this.pumpName});

  @override
  State<PumpDetailScreen> createState() => _PumpDetailScreenState();
}

class _PumpDetailScreenState extends State<PumpDetailScreen> {
  final _service = PumpService();
  final _lang = LangService();

  // ⚠️ TEST UNIQUEMENT — voir pump_fake_data.dart pour désactiver
  // partout d'un coup (my_robots_screen.dart et pump_list_screen.dart
  // utilisent la même source, les chiffres restent cohérents entre
  // tous les écrans).
  static const bool _useFakeData = PumpFakeData.enabled;

  models.Document? _pump;
  List<models.Document> _sessions = [];
  bool _loading = true;
  bool _renaming = false;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _nameCtrl = TextEditingController(text: widget.pumpName);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    if (_useFakeData) {
      await _loadFakeData();
      return;
    }

    final pump = await _service.getPump(widget.pumpId);
    final sessions = await _service.getPumpSessions(widget.pumpId);
    if (mounted) {
      setState(() {
        _pump = pump;
        _sessions = sessions;
        _loading = false;
        if (pump != null) {
          _nameCtrl.text = pump.data['name'] as String? ?? widget.pumpName;
        }
      });
    }
  }

  // Fausses sessions étalées sur les 3 dernières semaines, durées et
  // résine variables — juste pour tester l'affichage visuellement,
  // sans jamais toucher à Appwrite.
  Future<void> _loadFakeData() async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      setState(() {
        _pump = PumpFakeData.pumpFor(widget.pumpId, widget.pumpName);
        _sessions = PumpFakeData.sessionsFor(widget.pumpId);
        _loading = false;
      });
    }
  }

  Future<void> _saveRename() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    setState(() => _renaming = false);
    if (_useFakeData) {
      // Pas d'écriture réseau en mode test — juste visuel.
      setState(() {});
      return;
    }
    await _service.renamePump(widget.pumpId, newName);
    _load();
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    if (m > 0) return '${m}min${s.toString().padLeft(2, '0')}';
    return '${s}s';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
           '${d.month.toString().padLeft(2, '0')}/${d.year} '
           '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = (_pump?.data['totalRuntimeSeconds'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: _renaming
          ? TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true, border: InputBorder.none),
              onSubmitted: (_) => _saveRename())
          : Text(_nameCtrl.text.isEmpty ? widget.pumpName : _nameCtrl.text,
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: Icon(_renaming ? Icons.check : Icons.edit,
              color: const Color(0xFF22D3EE), size: 20),
            onPressed: _renaming
              ? _saveRename
              : () => setState(() => _renaming = true)),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: Color(0xFF22D3EE)))
        : RefreshIndicator(
            onRefresh: _load,
            color: const Color(0xFF22D3EE),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _totalTimeCard(totalSeconds),
                const SizedBox(height: 20),
                Text(_lang.t('pumpDetailHistoryTitle'),
                  style: TextStyle(color: Colors.grey[500], fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                if (_sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(_lang.t('pumpDetailNoSessionsYet'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12))))
                else
                  ..._sessions.map(_sessionTile),
              ],
            ),
          ),
    );
  }

  Widget _totalTimeCard(int totalSeconds) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.25))),
      child: Column(children: [
        Text(_lang.t('pumpDetailTotalTimeLabel'),
          style: TextStyle(color: Colors.grey[500], fontSize: 10,
            fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        Text(_formatDuration(totalSeconds),
          style: const TextStyle(color: Color(0xFF22D3EE),
            fontWeight: FontWeight.w900, fontSize: 32)),
        const SizedBox(height: 6),
        Text('${_sessions.length} ${_lang.t('pumpDetailSessionsSuffix')}',
          style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      ]),
    );
  }

  Widget _sessionTile(models.Document session) {
    final d = session.data;
    final duration = (d['durationSeconds'] as num?)?.toInt() ?? 0;
    final resin = (d['resinUsedL'] as num?)?.toDouble() ?? 0;
    final date = _formatDate(d['startedAt'] as String?);
    final location = d['location'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.play_arrow,
            color: Color(0xFF22D3EE), size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(date, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 3),
          Row(children: [
            Icon(Icons.schedule, color: Colors.grey[600], size: 11),
            const SizedBox(width: 3),
            Text(_formatDuration(duration),
              style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(width: 10),
            Icon(Icons.water_drop_outlined, color: Colors.grey[600], size: 11),
            const SizedBox(width: 3),
            Text('${resin.toStringAsFixed(2)} L',
              style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ]),
          if (location != null) ...[
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.place_outlined, color: Colors.grey[600], size: 11),
              const SizedBox(width: 3),
              Expanded(child: Text(location,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ])),
      ]),
    );
  }
}
