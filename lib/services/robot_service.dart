// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class RobotService {
  static const String endpoint    = 'https://cloud.appwrite.io/v1';
  static const String projectId   = '69ccd61d0017c7eaedee';
  static const String databaseId  = '69cd0f11001c948b59e9';
  static const String robotsTable = 'robots';
  static const String bucketId    = '6a2a559d000fadb5b207';

  late Client    _client;
  late Databases _db;
  late Storage   _storage;

  RobotService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db      = Databases(_client);
    _storage = Storage(_client);
  }

  // ── Vérifier si un robot existe déjà ─────────────────────────────────────
  Future<models.Document?> getRobotBySerial(String serial) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId,
        collectionId: robotsTable,
        queries: [Query.equal('serial', serial)],
      );
      if (result.documents.isNotEmpty) return result.documents.first;
    } catch (e) { /* ignore */ }
    return null;
  }

  // ── Enregistrer un robot ──────────────────────────────────────────────────
  Future<models.Document> registerRobot({
    required String serial,
    required String company,
    required String userId,
    required int    serie,
    required String year,
    required int    number,
  }) async {
    return await _db.createDocument(
      databaseId: databaseId,
      collectionId: robotsTable,
      documentId: ID.unique(),
      data: {
        'serial':  serial,
        'company': company,
        'userID':  userId,
        'serie':   serie,
        'year':    year,
        'number':  number,
      },
    );
  }

  // ── Récupérer tous les robots d'un utilisateur ────────────────────────────
  Future<List<models.Document>> getUserRobots(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId,
        collectionId: robotsTable,
        queries: [Query.equal('userID', userId)],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  // ── Récupérer tous les robots d'une entreprise ────────────────────────────
  Future<List<models.Document>> getCompanyRobots(String company) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId,
        collectionId: robotsTable,
        queries: [
          Query.equal('company', company),
          Query.orderAsc('number'),
        ],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  // ── Récupérer TOUS les robots (admin / super_admin) ───────────────────────
  Future<List<models.Document>> getAllRobots() async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId,
        collectionId: robotsTable,
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  // ── Récupérer l'historique d'un robot ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> getHistory(String documentId) async {
    try {
      final doc = await _db.getDocument(
        databaseId: databaseId,
        collectionId: robotsTable,
        documentId: documentId,
      );
      final raw = doc.data['history'] as String? ?? '';
      if (raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  // ── Uploader une image dans Storage, retourne le fileId ──────────────────
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final file = await _storage.createFile(
      bucketId: bucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(bytes: bytes, filename: filename),
    );
    return file.$id;
  }

  // ── Construire l'URL de preview d'un fichier Storage ─────────────────────
  String getImagePreviewUrl(String fileId) {
    return '$endpoint/storage/buckets/$bucketId/files/$fileId/preview'
        '?project=$projectId&width=400&height=400&gravity=center&quality=80';
  }

  // ── Construire l'URL de visualisation complète ────────────────────────────
  String getImageViewUrl(String fileId) {
    return '$endpoint/storage/buckets/$bucketId/files/$fileId/view'
        '?project=$projectId';
  }

  // ── Ajouter une entrée dans l'historique ──────────────────────────────────
  // [imageBytes] : liste de Uint8List (images brutes) — uploadées dans Storage
  // L'historique JSON ne stocke que les fileId, jamais le base64
  Future<void> addHistoryEntry(String documentId, {
    required String date,
    required String type,
    required String piece,
    required String technicien,
    String client = '',
    required String description,
    List<Uint8List> imageBytes = const [],
    List<String> imageNames  = const [],
  }) async {
    // 1. Uploader chaque image → récupérer les fileId
    final List<String> fileIds = [];
    for (int i = 0; i < imageBytes.length; i++) {
      final name = i < imageNames.length ? imageNames[i] : 'img_$i.jpg';
      final fileId = await uploadImage(imageBytes[i], name);
      fileIds.add(fileId);
    }

    // 2. Lire l'historique existant
    final current = await getHistory(documentId);

    // 3. Insérer la nouvelle entrée en tête
    current.insert(0, {
      'entryId':     ID.unique(),  // ← identifiant stable pour édition/suppression
      'date':        date,
      'type':        type,
      'piece':       piece,
      'technicien':  technicien,
      'client':      client,
      'description': description,
      'images':      fileIds,   // ← fileId uniquement, pas de base64
    });

    // 4. Persister
    await _db.updateDocument(
      databaseId: databaseId,
      collectionId: robotsTable,
      documentId: documentId,
      data: {'history': jsonEncode(current)},
    );
  }

  // ── Modifier une entrée existante de l'historique ─────────────────────────
  // [keepImageIds] : fileId des images existantes à conserver (celles retirées
  // par l'utilisateur ne sont PAS supprimées du Storage, juste détachées)
  // [newImageBytes]/[newImageNames] : nouvelles photos à uploader et ajouter
  Future<void> updateHistoryEntry(String documentId, String entryId, {
    required String date,
    required String type,
    required String piece,
    required String technicien,
    String client = '',
    required String description,
    List<String> keepImageIds = const [],
    List<Uint8List> newImageBytes = const [],
    List<String> newImageNames = const [],
  }) async {
    // 1. Uploader les nouvelles images
    final List<String> newFileIds = [];
    for (int i = 0; i < newImageBytes.length; i++) {
      final name = i < newImageNames.length ? newImageNames[i] : 'img_$i.jpg';
      final fileId = await uploadImage(newImageBytes[i], name);
      newFileIds.add(fileId);
    }

    // 2. Lire l'historique existant et localiser l'entrée
    final current = await getHistory(documentId);
    final index = current.indexWhere((e) => e['entryId'] == entryId);
    if (index == -1) return; // entrée introuvable, on n'écrit rien

    // 3. Remplacer l'entrée en conservant son entryId d'origine
    current[index] = {
      'entryId':     entryId,
      'date':        date,
      'type':        type,
      'piece':       piece,
      'technicien':  technicien,
      'client':      client,
      'description': description,
      'images':      [...keepImageIds, ...newFileIds],
    };

    // 4. Persister
    await _db.updateDocument(
      databaseId: databaseId,
      collectionId: robotsTable,
      documentId: documentId,
      data: {'history': jsonEncode(current)},
    );
  }

  // ── Supprimer une entrée de l'historique ──────────────────────────────────
  // Ne supprime pas les fichiers Storage associés (suppression douce, JSON
  // uniquement) afin d'éviter toute perte accidentelle de média partagé.
  Future<void> deleteHistoryEntry(String documentId, String entryId) async {
    final current = await getHistory(documentId);
    current.removeWhere((e) => e['entryId'] == entryId);

    await _db.updateDocument(
      databaseId: databaseId,
      collectionId: robotsTable,
      documentId: documentId,
      data: {'history': jsonEncode(current)},
    );
  }
}
