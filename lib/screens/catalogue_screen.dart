// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/lang_service.dart';
import '../widgets/lang_selector.dart';
import 'bzlight_parts_screen.dart';

class CatalogueScreen extends StatelessWidget {
  final String userRole;
  final List<String> userProducts;

  const CatalogueScreen({
    super.key,
    required this.userRole,
    required this.userProducts,
  });

  List<Map<String, dynamic>> _getProducts(LangService lang) => [
    {
      'id'      : 'bzlight',
      'name'    : lang.t('bzlight'),
      'desc'    : lang.t('bzlightDesc'),
      'color'   : 0xFFEAB308,
      'icon'    : Icons.bolt,
      'image'   : 'assets/bzlight.png',
      'features': [
        lang.t('featMilling'),
        lang.t('featHDCamera'),
        lang.t('featRange'),
        lang.t('featPilot'),
      ],
    },
    {
      'id'      : 'bzvision',
      'name'    : lang.t('bzvision'),
      'desc'    : lang.t('bzvisionDesc'),
      'color'   : 0xFF22D3EE,
      'icon'    : Icons.videocam,
      'features': [
        lang.t('featLiveStream'),
        lang.t('featCaptures'),
        lang.t('featAutoPDF'),
        lang.t('featPipeScheme'),
      ],
    },
    {
      'id'      : 'pompe',
      'name'    : lang.t('pompe'),
      'desc'    : lang.t('pompeDesc'),
      'color'   : 0xFFA855F7,
      'icon'    : Icons.science,
      'features': [
        lang.t('featIAVolume'),
        lang.t('featRealTime'),
        lang.t('featPDFReport'),
        lang.t('featWifiReady'),
      ],
    },
    {
      'id'      : 'tracteur',
      'name'    : lang.t('tracteur'),
      'desc'    : lang.t('tracteurDesc'),
      'color'   : 0xFF3B82F6,
      'icon'    : Icons.directions_car,
      'features': [
        lang.t('featModular'),
        lang.t('featSafety'),
        lang.t('featAllTerrain'),
        lang.t('featHighPower'),
      ],
    },
  ];

  Future<void> _contactBZBots(
      BuildContext context, String productName, LangService lang) async {
    final subject = Uri.encodeComponent(
      '${lang.t('accessRequestSubject')}$productName');
    final body = Uri.encodeComponent(lang.t('accessRequestBody'));
    final uri  = Uri.parse(
      'mailto:contact@bzbots.com?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(lang.t('contactUsEmail')),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang     = LangService();
    final products = _getProducts(lang);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(lang.t('catalogUpper'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2)),
        actions: const [LangSelector(), SizedBox(width: 8)],
      ),
      body: Column(children: [

        // ── Banner ──────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            border: Border(bottom: BorderSide(
              color: Colors.white.withOpacity(0.06)))),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.3))),
              child: const Icon(Icons.grid_view,
                color: Color(0xFF22D3EE), size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lang.t('bzbotsProducts'),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 14)),
                Text(
                  '${userProducts.length} ${lang.t('activeProductsCount')}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ])),
          ]),
        ),

        // ── Liste produits ──────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: products.length,
            itemBuilder: (_, i) {
              final p        = products[i];
              final id       = p['id']       as String;
              final name     = p['name']     as String;
              final desc     = p['desc']     as String;
              final color    = Color(p['color'] as int);
              final icon     = p['icon']     as IconData;
              final features = p['features'] as List<String>;
              final image    = p['image']    as String?;
              final isActive = userRole == 'super_admin' ||
                               userRole == 'admin'       ||
                               userProducts.contains(id);

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                      ? color.withOpacity(0.3)
                      : Colors.white.withOpacity(0.06)),
                  boxShadow: isActive ? [BoxShadow(
                    color: color.withOpacity(0.08),
                    blurRadius: 16)] : null),
                child: Column(children: [

                  // ── Header produit ────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.05),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20))),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withOpacity(0.3))),
                        child: image != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                  Icon(icon, color: color, size: 24)))
                          : Icon(icon, color: color, size: 24)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(desc, style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11, height: 1.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        ])),
                      const SizedBox(width: 8),
                      // Badge statut
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive
                            ? Colors.green.withOpacity(0.12)
                            : Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                              ? Colors.green.withOpacity(0.4)
                              : Colors.grey.withOpacity(0.2))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            isActive
                              ? Icons.check_circle
                              : Icons.lock_outline,
                            color: isActive
                              ? Colors.green
                              : Colors.grey[600],
                            size: 12),
                          const SizedBox(width: 5),
                          Text(
                            isActive
                              ? lang.t('activeStatus')
                              : lang.t('inactiveStatus'),
                            style: TextStyle(
                              color: isActive
                                ? Colors.green
                                : Colors.grey[600],
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                        ])),
                    ]),
                  ),

                  // ── Features ─────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      children: features.map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: color.withOpacity(0.15))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check, color: color, size: 10),
                          const SizedBox(width: 4),
                          Text(f, style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                        ]),
                      )).toList(),
                    ),
                  ),

                  // ── Bouton pièces détachées (BzLight uniquement) ──
                  if (id == 'bzlight' && isActive)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                            builder: (_) => const BzlightPartsScreen())),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAB308).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFEAB308).withOpacity(0.3))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.build_outlined,
                                color: Color(0xFFEAB308), size: 16),
                              const SizedBox(width: 8),
                              const Text('Voir les pièces détachées',
                                style: TextStyle(
                                  color: Color(0xFFEAB308),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1)),
                            ])),
                      ),
                    ),

                  // ── Action ───────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: isActive
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.2))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                              const SizedBox(width: 8),
                              Text(lang.t('moduleActivatedOnAccount'),
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                            ]))
                      : GestureDetector(
                          onTap: () => _contactBZBots(context, name, lang),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: color.withOpacity(0.3))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.mail_outline,
                                  color: color, size: 16),
                                const SizedBox(width: 8),
                                Text(lang.t('requestAccess'),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                              ])),
                        ),
                  ),
                ]),
              );
            },
          ),
        ),

        // ── Footer contact ──────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            border: Border(top: BorderSide(
              color: Colors.white.withOpacity(0.06)))),
          child: Row(children: [
            Icon(Icons.support_agent,
              color: Colors.grey[600], size: 14),
            const SizedBox(width: 8),
            Text('contact@bzbots.com',
              style: TextStyle(color: Colors.grey[500],
                fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('mailto:contact@bzbots.com');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withOpacity(0.3))),
                child: Text(lang.t('contactUsBtn'),
                  style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontSize: 10,
                    fontWeight: FontWeight.w900))),
            ),
          ]),
        ),
      ]),
    );
  }
}