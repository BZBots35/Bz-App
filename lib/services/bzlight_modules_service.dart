import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class BzlightModulesService {
  static const String endpoint     = 'https://cloud.appwrite.io/v1';
  static const String projectId    = '69ccd61d0017c7eaedee';
  static const String databaseId   = '69cd0f11001c948b59e9';
  static const String collectionId = 'bzlight_modules';

  late Client    _client;
  late Databases _db;

  BzlightModulesService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
  }

  /// Récupère tous les sous-modules d'une série (BZL1, BZL2, BZL3, BZL4),
  /// triés selon l'attribut 'order'.
  Future<List<Map<String, String>>> getModulesByBzl(String bzl) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: collectionId,
        queries     : [
          Query.equal('bzl', bzl),
          Query.orderAsc('order'),
          Query.limit(200),
        ],
      );
      return result.documents.map((doc) => {
        'docId'   : doc.$id,
        'id'      : doc.data['moduleId'] as String? ?? '',
        'img'     : doc.data['img']      as String? ?? '',
        'version' : doc.data['version']  as String? ?? '',
        'nameKey' : doc.data['nameKey']  as String? ?? '',
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Met à jour la version d'un sous-module (réservé distributeur/admin/super_admin)
  Future<void> updateModuleVersion(String docId, String version) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: collectionId,
      documentId  : docId,
      data        : {'version': version},
    );
  }
}
