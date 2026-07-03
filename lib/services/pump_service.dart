// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class PumpService {
  static const String endpoint         = 'https://cloud.appwrite.io/v1';
  static const String projectId        = '69ccd61d0017c7eaedee';
  static const String databaseId       = '69cd0f11001c948b59e9';
  static const String chantiersTable   = 'pump_chantiers';
  static const String canalisationsTable = 'pump_canalisations';

  late Client    _client;
  late Databases _db;

  PumpService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
  }

  // ── Chantiers ──────────────────────────────────
  Future<List<models.Document>> getChantiers(String userId, String role) async {
    try {
      final queries = (role == 'super_admin' || role == 'admin')
        ? <String>[] : [Query.equal('userID', userId)];
      final result = await _db.listDocuments(
        databaseId: databaseId, collectionId: chantiersTable, queries: queries);
      return result.documents;
    } catch (e) { return []; }
  }

  Future<models.Document> createChantier({
    required String nom, required String ville, required String rue,
    required String batiment, required String date,
    required String userId, required String company,
    required String resinType, required String epaisseur,
    required int desiredPasses,
  }) async {
    return await _db.createDocument(
      databaseId: databaseId, collectionId: chantiersTable,
      documentId: ID.unique(),
      data: {
        'nom': nom, 'ville': ville, 'rue': rue, 'batiment': batiment,
        'date': date, 'userID': userId, 'company': company,
        'resinType': resinType, 'epaisseur': epaisseur,
        'desiredPasses': desiredPasses,
      });
  }

  Future<void> updateChantierParams(String docId,
      String resinType, String epaisseur, int desiredPasses) async {
    await _db.updateDocument(
      databaseId: databaseId, collectionId: chantiersTable,
      documentId: docId,
      data: {'resinType': resinType, 'epaisseur': epaisseur,
             'desiredPasses': desiredPasses});
  }

  Future<void> updateChantier(String docId, {
    required String nom, required String ville,
    required String rue, required String batiment,
    required String date,
  }) async {
    await _db.updateDocument(
      databaseId: databaseId, collectionId: chantiersTable,
      documentId: docId,
      data: {'nom': nom, 'ville': ville, 'rue': rue,
             'batiment': batiment, 'date': date});
  }

  Future<void> deleteChantier(String docId) async {
    await _db.deleteDocument(databaseId: databaseId,
      collectionId: chantiersTable, documentId: docId);
  }

  // ── Canalisations ──────────────────────────────
  Future<List<models.Document>> getCanalisations(String chantierId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId, collectionId: canalisationsTable,
        queries: [Query.equal('chantierID', chantierId)]);
      return result.documents;
    } catch (e) { return []; }
  }

  Future<models.Document> createCanalisation({
    required String chantierId, required String label,
    required String longueur, required String diametre,
    required int passes, required String userId,
  }) async {
    return await _db.createDocument(
      databaseId: databaseId, collectionId: canalisationsTable,
      documentId: ID.unique(),
      data: {
        'chantierID': chantierId, 'label': label,
        'longueur': longueur, 'diametre': diametre,
        'passes': passes, 'statut': 'en_attente', 'userID': userId,
      });
  }

  Future<void> updateCanalisation(String docId, {
    String? label, String? longueur, String? diametre,
    int? passes, String? statut,
  }) async {
    final data = <String, dynamic>{};
    if (label    != null) data['label']    = label;
    if (longueur != null) data['longueur'] = longueur;
    if (diametre != null) data['diametre'] = diametre;
    if (passes   != null) data['passes']   = passes;
    if (statut   != null) data['statut']   = statut;
    await _db.updateDocument(databaseId: databaseId,
      collectionId: canalisationsTable, documentId: docId, data: data);
  }

  Future<void> deleteCanalisation(String docId) async {
    await _db.deleteDocument(databaseId: databaseId,
      collectionId: canalisationsTable, documentId: docId);
  }
}
