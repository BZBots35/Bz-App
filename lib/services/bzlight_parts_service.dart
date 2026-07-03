import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class BzlightPartsService {
  static const String endpoint     = 'https://cloud.appwrite.io/v1';
  static const String projectId    = '69ccd61d0017c7eaedee';
  static const String databaseId   = '69cd0f11001c948b59e9';
  static const String collectionId = 'bzlight_parts';

  late Client    _client;
  late Databases _db;

  BzlightPartsService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
  }

  /// Récupère toutes les pièces d'une série
  Future<List<models.Document>> getPartsBySeries(String series) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: collectionId,
        queries     : [
          Query.equal('series', series),
          Query.orderAsc('order'),
        ],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  /// Récupère les sous-assemblages distincts d'une série
  Future<List<String>> getAssembliesBySeries(String series) async {
    final parts = await getPartsBySeries(series);
    final assemblies = <String>[];
    for (final part in parts) {
      final assembly = part.data['assembly'] as String? ?? '';
      if (assembly.isNotEmpty && !assemblies.contains(assembly)) {
        assemblies.add(assembly);
      }
    }
    return assemblies;
  }

  /// Met à jour la version d'une pièce (réservé distributeur/admin/super_admin)
  Future<void> updatePartVersion(String partId, String version) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: collectionId,
      documentId  : partId,
      data        : {'version': version},
    );
  }
}