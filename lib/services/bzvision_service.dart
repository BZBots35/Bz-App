// ignore_for_file: deprecated_member_use
import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class BzVisionService {
  static const String endpoint           = 'https://cloud.appwrite.io/v1';
  static const String projectId          = '69ccd61d0017c7eaedee';
  static const String databaseId         = '69cd0f11001c948b59e9';
  static const String chantiersTable     = 'chantiers';
  static const String canalisationsTable = 'canalisations';
  static const String inspectionsTable   = 'inspections';
  static const String videosBucketId     = 'bzvision_videos';

  late Client    _client;
  late Databases _db;
  late Storage   _storage;

  BzVisionService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db      = Databases(_client);
    _storage = Storage(_client);
  }

  // ── Chantiers ─────────────────────────────────
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
    required String nom, required String adresse, required String client,
    required String date, required String statut,
    required String userId, required String company,
  }) async {
    return await _db.createDocument(
      databaseId: databaseId, collectionId: chantiersTable,
      documentId: ID.unique(),
      data: {'nom': nom, 'adresse': adresse, 'client': client,
             'date': date, 'statut': statut, 'userID': userId, 'company': company});
  }

  Future<void> updateChantierStatut(String docId, String statut) async {
    await _db.updateDocument(databaseId: databaseId,
      collectionId: chantiersTable, documentId: docId, data: {'statut': statut});
  }

  Future<void> updateChantier({
    required String docId,
    required String nom,
    required String adresse,
    required String client,
  }) async {
    await _db.updateDocument(
      databaseId: databaseId, collectionId: chantiersTable,
      documentId: docId,
      data: {'nom': nom, 'adresse': adresse, 'client': client});
  }

  Future<void> deleteChantier(String docId) async {
    await _db.deleteDocument(databaseId: databaseId,
      collectionId: chantiersTable, documentId: docId);
  }

  // ── Canalisations ─────────────────────────────
  Future<List<models.Document>> getCanalisations(String chantierId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId, collectionId: canalisationsTable,
        queries: [Query.equal('chantierID', chantierId)]);
      return result.documents;
    } catch (e) { return []; }
  }

  Future<models.Document> createCanalisation({
    required String chantierId, required String nom,
    required String diametre, required String longueur,
    required String materiau, required String statut, required String observations,
    String noeudAmont = '', String noeudAval = '',
    String forme = 'Circulaire', String sensEcoulement = 'Gravitaire',
    String typeEffluent = 'EU',
    String profondeurAmont = '', String profondeurAval = '',
  }) async {
    return await _db.createDocument(
      databaseId: databaseId, collectionId: canalisationsTable,
      documentId: ID.unique(),
      data: {
        'chantierID': chantierId, 'nom': nom, 'diametre': diametre,
        'longueur': longueur, 'materiau': materiau,
        'statut': statut, 'observations': observations,
        'noeudAmont': noeudAmont, 'noeudAval': noeudAval,
        'forme': forme, 'sensEcoulement': sensEcoulement,
        'typeEffluent': typeEffluent,
        'profondeurAmont': profondeurAmont,
        'profondeurAval': profondeurAval,
      });
  }

  Future<void> updateCanalisationStatut(String docId, String statut) async {
    await _db.updateDocument(databaseId: databaseId,
      collectionId: canalisationsTable, documentId: docId,
      data: {'statut': statut});
  }

  Future<void> updateCanalisation({
    required String docId,
    required String nom,
    required String diametre,
    required String longueur,
    required String materiau,
    required String noeudAmont,
    required String noeudAval,
    required String forme,
    required String sensEcoulement,
    required String typeEffluent,
    required String profondeurAmont,
    required String profondeurAval,
  }) async {
    await _db.updateDocument(
      databaseId: databaseId, collectionId: canalisationsTable,
      documentId: docId,
      data: {
        'nom': nom, 'diametre': diametre, 'longueur': longueur,
        'materiau': materiau, 'noeudAmont': noeudAmont, 'noeudAval': noeudAval,
        'forme': forme, 'sensEcoulement': sensEcoulement,
        'typeEffluent': typeEffluent,
        'profondeurAmont': profondeurAmont, 'profondeurAval': profondeurAval,
      });
  }

  Future<void> deleteCanalisation(String docId) async {
    await _db.deleteDocument(databaseId: databaseId,
      collectionId: canalisationsTable, documentId: docId);
  }

  // ── Inspections ───────────────────────────────
  Future<List<models.Document>> getInspections(String canalisationId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId, collectionId: inspectionsTable,
        queries: [Query.equal('canalisationID', canalisationId)]);
      return result.documents;
    } catch (e) { return []; }
  }

  Future<models.Document> createInspection({
    required String canalisationId, required String chantierId,
    required String date, required String operateur,
    required String observations, required String userId,
    String objectifInspection = '',
    String attentes           = '',
    String niveauDetail       = '1',
  }) async {
    return await _db.createDocument(
      databaseId: databaseId, collectionId: inspectionsTable,
      documentId: ID.unique(),
      data: {
        'canalisationID': canalisationId, 'chantierID': chantierId,
        'date': date, 'operateur': operateur,
        'observations': observations, 'userID': userId,
        'objectifInspection': objectifInspection,
        'attentes':           attentes,
        'niveauDetail':       niveauDetail,
      });
  }

  Future<void> deleteInspection(String docId) async {
    await _db.deleteDocument(databaseId: databaseId,
      collectionId: inspectionsTable, documentId: docId);
  }

  // ── Nœuds réseau ──────────────────────────────
  static const String noeudsTable = 'noeuds';

  Future<List<models.Document>> getNoeuds(String chantierId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId, collectionId: noeudsTable,
        queries: [Query.equal('chantierID', chantierId)]);
      return result.documents;
    } catch (e) { return []; }
  }

  Future<models.Document> upsertNoeud({
    required String chantierId,
    required String noeudId,
    required String typeRaccordement,
    required String direction,
    required String angle,
    required String codeNF,
    required String observation,
  }) async {
    try {
      final existing = await _db.listDocuments(
        databaseId: databaseId, collectionId: noeudsTable,
        queries: [
          Query.equal('chantierID', chantierId),
          Query.equal('noeudId', noeudId),
        ]);
      if (existing.documents.isNotEmpty) {
        return await _db.updateDocument(
          databaseId: databaseId, collectionId: noeudsTable,
          documentId: existing.documents.first.$id,
          data: {
            'typeRaccordement': typeRaccordement,
            'direction':        direction,
            'angle':            angle,
            'codeNF':           codeNF,
            'observation':      observation,
          });
      }
    } catch (_) {}
    return await _db.createDocument(
      databaseId: databaseId, collectionId: noeudsTable,
      documentId: ID.unique(),
      data: {
        'chantierID':       chantierId,
        'noeudId':          noeudId,
        'typeRaccordement': typeRaccordement,
        'direction':        direction,
        'angle':            angle,
        'codeNF':           codeNF,
        'observation':      observation,
      });
  }

  Future<void> deleteNoeud(String docId) async {
    try {
      await _db.deleteDocument(
        databaseId: databaseId, collectionId: noeudsTable,
        documentId: docId);
    } catch (_) {}
  }

  // ── Storage Vidéos ────────────────────────────

  Future<List<models.File>> listStorageVideos() async {
    try {
      final result = await _storage.listFiles(bucketId: videosBucketId);
      return result.files;
    } catch (e) { return []; }
  }

  Future<models.File?> uploadVideo({
    required String localPath,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final result = await _storage.createFile(
        bucketId: videosBucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: localPath, filename: filename),
        onProgress: onProgress != null
            ? (p) => onProgress(p.progress / 100) : null,
      );
      return result;
    } catch (e) { return null; }
  }

  Future<Uint8List?> downloadVideoBytes({
    required String fileId,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final bytes = await _storage.getFileDownload(
        bucketId: videosBucketId, fileId: fileId);
      return bytes;
    } catch (e) { return null; }
  }

  Future<bool> deleteStorageVideo(String fileId) async {
    try {
      await _storage.deleteFile(bucketId: videosBucketId, fileId: fileId);
      return true;
    } catch (e) { return false; }
  }

  String getVideoStreamUrl(String fileId) =>
      '$endpoint/storage/buckets/$videosBucketId/files/$fileId/view'
      '?project=$projectId';
}
