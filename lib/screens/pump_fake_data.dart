// ⚠️ FICHIER DE TEST UNIQUEMENT ⚠️
//
// Source unique de fausses données pour tester l'affichage des écrans
// pompe (temps cumulé, historique, lieux) sans jamais toucher à
// Appwrite. Centralisé ici pour que pump_detail_screen.dart,
// my_robots_screen.dart et pump_list_screen.dart affichent tous
// EXACTEMENT les mêmes chiffres — pas trois jeux de fausses données
// différents et incohérents entre eux.
//
// Pour désactiver et repasser en données réelles partout : mettre
// `enabled` à false ci-dessous, rien d'autre à toucher dans les écrans.
import 'package:appwrite/models.dart' as models;

class PumpFakeData {
  static const bool enabled = true;

  static const List<Map<String, dynamic>> _sessions = [
    {'daysAgo': 21, 'min': 42, 'resin': 5.4,  'location': 'Rennes — Rue de Paris'},
    {'daysAgo': 18, 'min': 15, 'resin': 1.8,  'location': 'Le Rheu — ZA du Guérin'},
    {'daysAgo': 14, 'min': 63, 'resin': 8.1,  'location': 'Cesson-Sévigné'},
    {'daysAgo': 9,  'min': 28, 'resin': 3.2,  'location': 'Bruz — Route de Laillé'},
    {'daysAgo': 6,  'min': 95, 'resin': 12.6, 'location': 'Rennes — Bd de Metz'},
    {'daysAgo': 3,  'min': 37, 'resin': 4.5,  'location': 'Vezin-le-Coquet'},
    {'daysAgo': 1,  'min': 51, 'resin': 6.9,  'location': 'Rennes — Avenue Janvier'},
  ];

  static int totalSeconds() =>
      _sessions.fold<int>(0, (sum, s) => sum + (s['min'] as int) * 60);

  static List<models.Document> sessionsFor(String pumpId) {
    final now = DateTime.now();
    return _sessions.map((s) {
      final startedAt = now.subtract(Duration(days: s['daysAgo'] as int));
      return models.Document.fromMap({
        '\$id': 'fake_${s['daysAgo']}',
        '\$collectionId': 'pump_sessions',
        '\$databaseId': 'fake',
        '\$createdAt': startedAt.toIso8601String(),
        '\$updatedAt': startedAt.toIso8601String(),
        '\$permissions': [],
        'pumpId': pumpId,
        'startedAt': startedAt.toIso8601String(),
        'durationSeconds': (s['min'] as int) * 60,
        'resinUsedL': s['resin'],
        'location': s['location'],
      });
    }).toList();
  }

  static models.Document pumpFor(String pumpId, String name) {
    final now = DateTime.now();
    return models.Document.fromMap({
      '\$id': pumpId,
      '\$collectionId': 'pump_pumps',
      '\$databaseId': 'fake',
      '\$createdAt': now.toIso8601String(),
      '\$updatedAt': now.toIso8601String(),
      '\$permissions': [],
      'name': name,
      'totalRuntimeSeconds': totalSeconds(),
    });
  }
}
