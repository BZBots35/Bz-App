// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'pump_screen.dart';
import 'pump_direct_screen.dart';
import '../services/lang_service.dart';

/// Écran d'accueil pompe : point d'entrée avant tout le reste.
/// Propose deux chemins :
///  - "Chantiers" → écran de liste/création de chantiers (PumpScreen)
///  - "Accéder à la pompe sans les paramètres" → contrôle direct de la
///    pompe, sans passer par un chantier (PumpDirectScreen)
class PumpHubScreen extends StatefulWidget {
  const PumpHubScreen({super.key});

  @override
  State<PumpHubScreen> createState() => _PumpHubScreenState();
}

class _PumpHubScreenState extends State<PumpHubScreen> {
  final _lang = LangService();

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
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
          Text(_lang.t('pumpHubScreenTitle'),
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 14,
              letterSpacing: 1.5)),
        ]),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _hubCard(
              context: context,
              icon: Icons.construction,
              color: const Color(0xFF22D3EE),
              title: _lang.t('pumpHubChantiersTitle'),
              subtitle: _lang.t('pumpHubChantiersSubtitle'),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const PumpScreen())),
            ),
            const SizedBox(height: 16),
            _hubCard(
              context: context,
              icon: Icons.bolt,
              color: Colors.amber,
              title: _lang.t('pumpHubDirectTitle'),
              subtitle: _lang.t('pumpHubDirectSubtitle'),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const PumpDirectScreen())),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hubCard({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 14)]),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.35))),
            child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(
              color: Colors.grey[500], fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: color, size: 22),
        ]),
      ),
    );
  }
}
