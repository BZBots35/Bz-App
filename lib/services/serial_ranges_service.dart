import 'package:appwrite/appwrite.dart';

class SerialRangesService {
  static const String endpoint     = 'https://cloud.appwrite.io/v1';
  static const String projectId    = '69ccd61d0017c7eaedee';
  static const String databaseId   = '69cd0f11001c948b59e9';
  static const String collectionId = 'bzlight_serial_ranges';

  late Client    _client;
  late Databases _db;

  SerialRangesService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
  }

  /// Récupère toutes les plages définies, triées par année puis par minNumber.
  Future<List<Map<String, dynamic>>> getAllRanges() async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: collectionId,
        queries     : [
          Query.orderAsc('year'),
          Query.orderAsc('minNumber'),
          Query.limit(200),
        ],
      );
      return result.documents.map((doc) => {
        'docId'     : doc.$id,
        'year'      : doc.data['year']      as String,
        'minNumber' : doc.data['minNumber'] as int,
        'maxNumber' : doc.data['maxNumber'] as int,
        'serie'     : doc.data['serie']     as int,
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Trouve la série correspondant à une année + numéro donnés.
  /// Retourne null si aucune plage ne correspond (numéro de série inconnu).
  Future<int?> findSerie(String year, int number) async {
    final ranges = await getAllRanges();
    for (final r in ranges) {
      if (r['year'] == year && number >= r['minNumber'] && number <= r['maxNumber']) {
        return r['serie'] as int;
      }
    }
    return null;
  }

  /// Crée une nouvelle plage.
  Future<void> createRange({
    required String year,
    required int minNumber,
    required int maxNumber,
    required int serie,
  }) async {
    await _db.createDocument(
      databaseId  : databaseId,
      collectionId: collectionId,
      documentId  : ID.unique(),
      data        : {
        'year': year, 'minNumber': minNumber,
        'maxNumber': maxNumber, 'serie': serie,
      },
    );
  }

  /// Met à jour une plage existante.
  Future<void> updateRange(String docId, {
    required String year,
    required int minNumber,
    required int maxNumber,
    required int serie,
  }) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: collectionId,
      documentId  : docId,
      data        : {
        'year': year, 'minNumber': minNumber,
        'maxNumber': maxNumber, 'serie': serie,
      },
    );
  }

  /// Supprime une plage.
  Future<void> deleteRange(String docId) async {
    await _db.deleteDocument(
      databaseId  : databaseId,
      collectionId: collectionId,
      documentId  : docId,
    );
  }
}
