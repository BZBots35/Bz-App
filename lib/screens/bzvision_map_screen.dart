// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;

class BzVisionMapScreen extends StatelessWidget {
  final List<models.Document> chantiers;
  const BzVisionMapScreen({super.key, required this.chantiers});

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
        title: const Text('CARTE CHANTIERS',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
      ),
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.map_outlined, color: Colors.grey[700], size: 64),
        const SizedBox(height: 16),
        const Text('Carte en cours de développement',
          style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        Text('${chantiers.length} chantier(s) enregistré(s)',
          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ])),
    );
  }
}