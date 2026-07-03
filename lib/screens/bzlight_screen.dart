// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/lang_service.dart';
import '../services/auth_service.dart';
import '../services/robot_service.dart';
import '../services/serial_ranges_service.dart';
import '../widgets/lang_selector.dart';
import 'bzlight_dashboard_screen.dart';

class BzLightScreen extends StatefulWidget {
  const BzLightScreen({super.key});
  @override
  State<BzLightScreen> createState() => _BzLightScreenState();
}

class _BzLightScreenState extends State<BzLightScreen> {
  final _serialCtrl  = TextEditingController(text: 'BZL-');
  final _companyCtrl = TextEditingController();
  final _lang        = LangService();
  final _auth        = AuthService();
  final _robots      = RobotService();
  final _ranges      = SerialRangesService();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final user = await _auth.getCurrentUser();
    if (user != null) {
      final company = await _auth.getUserCompany(user.$id);
      if (company.isNotEmpty && mounted) {
        setState(() => _companyCtrl.text = company);
      }
    }
  }

  void _formatSerial(String value) {
    String clean = value.replaceAll(RegExp(r'[^A-Z0-9\-]'), '').toUpperCase();
    if (!clean.startsWith('BZL-')) clean = 'BZL-';
    if (clean.length > 12) clean = clean.substring(0, 12);
    if (_serialCtrl.text != clean) {
      _serialCtrl.value = TextEditingValue(
        text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
  }

  Future<void> _authenticate() async {
    final serial = _serialCtrl.text.trim().toUpperCase();
    final regex  = RegExp(r'^BZL-(25|26)-(\d{5})$');
    final match  = regex.firstMatch(serial);
    setState(() => _error = null);

    if (match == null) {
      setState(() => _error = _lang.t('invalidSerial')); return;
    }

    final year   = match.group(1)!;
    final number = int.parse(match.group(2)!);

    final company = _companyCtrl.text.trim();
    if (company.isEmpty) {
      setState(() => _error = 'Veuillez saisir le nom de votre entreprise.'); return;
    }

    setState(() => _loading = true);

    final serie = await _ranges.findSerie(year, number);
    if (serie == null) {
      setState(() { _loading = false; _error = _lang.t('unknownSerial'); });
      return;
    }

    try {
      // Vérifier si ce robot existe déjà en base
      final existing = await _robots.getRobotBySerial(serial);

      if (existing != null) {
        // Robot déjà enregistré — vérifier que l'entreprise correspond
        final registeredCompany = existing.data['company'] as String;
        if (registeredCompany.toLowerCase() != company.toLowerCase()) {
          setState(() {
            _loading = false;
            _error   = 'Ce robot est déjà associé à une autre entreprise. Accès refusé.';
          });
          return;
        }
        // Entreprise correcte → accès direct au dashboard
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => BzLightDashboardScreen(
              serial: serial, serie: serie, year: year,
              number: number, company: registeredCompany)));
        }
      } else {
        // Nouveau robot → enregistrement
        final user = await _auth.getCurrentUser();
        if (user == null) {
          setState(() { _loading = false; _error = 'Erreur : utilisateur non connecté.'; });
          return;
        }
        await _robots.registerRobot(
          serial:  serial,
          company: company,
          userId:  user.$id,
          serie:   serie,
          year:    year,
          number:  number,
        );
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => BzLightDashboardScreen(
              serial: serial, serie: serie, year: year,
              number: number, company: company)));
        }
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Erreur : $e'; });
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
        title: const Text('BZLIGHT',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: const [LangSelector(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const SizedBox(height: 40),
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEAB308).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.3)),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFEAB308).withOpacity(0.2), blurRadius: 24)],
              ),
              child: const Icon(Icons.flash_on, color: Color(0xFFEAB308), size: 36),
            ),
            const SizedBox(height: 20),
            const Text('BzLight', style: TextStyle(color: Colors.white,
              fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(_lang.t('authTitle'),
              style: TextStyle(color: Colors.grey[500], fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: 48),
            Align(alignment: Alignment.centerLeft,
              child: Text(_lang.t('serial'),
                style: TextStyle(color: Colors.grey[400], fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 3))),
            const SizedBox(height: 16),
            // Champ série
            TextField(
              controller: _serialCtrl,
              onChanged: _formatSerial,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'monospace'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.memory, color: Color(0xFFEAB308), size: 20),
                hintText: 'BZL-25-00001',
                hintStyle: TextStyle(color: Colors.grey[700], fontSize: 14, letterSpacing: 2),
                filled: true, fillColor: const Color(0xFF0D0D0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: const Color(0xFFEAB308).withOpacity(0.3))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: const Color(0xFFEAB308).withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEAB308), width: 1.5))),
            ),
            const SizedBox(height: 14),
            // Champ entreprise
            TextField(
              controller: _companyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: _lang.t('company'),
                labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                prefixIcon: Icon(Icons.business, color: Colors.grey[600], size: 20),
                filled: true, fillColor: const Color(0xFF0D0D0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEAB308), width: 1.5))),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Text(_error!, style: const TextStyle(color: Colors.red,
                  fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _authenticate,
                icon: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sync, size: 20),
                label: Text(_loading ? '...' : _lang.t('sync'),
                  style: const TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 13, letterSpacing: 2)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAB308), foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              ),
            ),
            const SizedBox(height: 24),
            Text(_lang.t('syncFormats'), textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 10)),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
