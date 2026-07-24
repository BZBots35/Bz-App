// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PumpService — version hors-ligne.
///
/// Principe :
/// - Lecture (getChantiers/getCanalisations) : essaie Appwrite si en ligne,
///   met à jour un cache local ; si hors ligne (ou erreur réseau), lit le cache.
/// - Écriture (create/update/delete) : si en ligne, comportement normal +
///   mise à jour du cache. Si hors ligne, appliqué immédiatement en local
///   (le technicien voit son changement tout de suite) ET mis en file
///   d'attente pour être rejoué vers Appwrite au retour du réseau.
///
/// ⚠️ Suppose que `models.Document` expose `toMap()` / `Document.fromMap()`
/// (standard dans le SDK Appwrite Dart). Si ta version du package appwrite
/// ne les a pas, dis-le-moi et j'adapte la sérialisation.
///
/// ⚠️ NOUVEAU : `passesData` sur `updateCanalisation` — stocke, par passe,
/// une courbe allégée épaisseur (mm) / métrage (m) sous forme de chaîne
/// JSON (ex: {"1": [[0.1, 0.82], [0.2, 0.79], ...], "2": [...]}).
/// Nécessite un attribut String sur la collection Appwrite
/// `pump_canalisations` (taille conseillée : au moins 50000 caractères,
/// pour tenir plusieurs passes sur une longue canalisation).
class PumpService {
  static const String endpoint           = 'https://cloud.appwrite.io/v1';
  static const String projectId          = '69ccd61d0017c7eaedee';
  static const String databaseId         = '69cd0f11001c948b59e9';
  static const String chantiersTable     = 'pump_chantiers';
  static const String canalisationsTable = 'pump_canalisations';

  late Client    _client;
  late Databases _db;
  StreamSubscription<dynamic>? _connectivitySub;

  PumpService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
    _startAutoSync();
  }

  // Écoute les changements de connectivité et rejoue automatiquement la
  // file d'attente hors-ligne dès qu'un accès Internet RÉEL revient (pas
  // juste une interface réseau — voir _isOnline()). Typiquement : tu
  // quittes le hotspot de la Pi et retrouves ton WiFi/4G habituel, tout
  // ce qui a été modifié en local pendant la déconnexion part vers
  // Appwrite sans action manuelle de ta part.
  void _startAutoSync() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) async {
      // Petite pause pour laisser le temps au réseau de vraiment se
      // stabiliser après un changement, avant de tester la joignabilité.
      await Future.delayed(const Duration(seconds: 2));
      if (await _isOnline()) {
        await syncPendingOperations();
      }
    });
  }

  /// À appeler si besoin de libérer proprement l'écoute réseau (rarement
  /// nécessaire ici, PumpService vit généralement toute la durée de l'app).
  void dispose() {
    _connectivitySub?.cancel();
  }

  // ─────────────────────────────────────────────
  // CONNECTIVITÉ
  // ─────────────────────────────────────────────

  // Vérifie qu'Appwrite est réellement joignable, pas juste qu'une
  // interface réseau existe. Important : un téléphone connecté au hotspot
  // WiFi local de la Pi (sans accès Internet) est vu comme "connecté" par
  // Connectivity().checkConnectivity(), alors qu'il ne peut pas du tout
  // atteindre Appwrite — sans ce vrai test, l'app tenterait des écritures
  // en ligne qui échouent/timeout au lieu de basculer proprement en file
  // d'attente hors-ligne.
  Future<bool> _isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) return false;

    try {
      final result = await InternetAddress.lookup('cloud.appwrite.io')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // CACHE LOCAL (lecture)
  // ─────────────────────────────────────────────

  Future<void> _cacheList(String key, List<models.Document> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = docs.map((d) => d.toMap()).toList();
    await prefs.setString(key, jsonEncode(raw));
  }

  Future<List<models.Document>> _readCachedList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((m) => models.Document.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Ajoute/replace un document dans une liste en cache (pour les écritures
  /// optimistes hors-ligne, sans devoir tout re-télécharger).
  Future<void> _upsertInCache(String key, models.Document doc) async {
    final current = await _readCachedList(key);
    final idx = current.indexWhere((d) => d.$id == doc.$id);
    if (idx >= 0) {
      current[idx] = doc;
    } else {
      current.add(doc);
    }
    await _cacheList(key, current);
  }

  Future<void> _removeIdFromCachesWithPrefix(String prefix, String docId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    for (final key in keys) {
      final current = await _readCachedList(key);
      final before = current.length;
      current.removeWhere((d) => d.$id == docId);
      if (current.length != before) await _cacheList(key, current);
    }
  }

  /// Fusionne `payload` dans le document mis en cache correspondant à
  /// `docId`, partout où il apparaît (potentiellement plusieurs clés de
  /// cache). Utilisé pour que les écritures hors-ligne (updateCanalisation,
  /// updateChantier...) soient visibles immédiatement dans l'app, sans
  /// attendre la synchronisation vers Appwrite.
  Future<void> _updateIdInCachesWithPrefix(
      String prefix, String docId, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    for (final key in keys) {
      final current = await _readCachedList(key);
      final idx = current.indexWhere((d) => d.$id == docId);
      if (idx < 0) continue;
      final merged = <String, dynamic>{
        '\$id': current[idx].$id,
        '\$collectionId': current[idx].$collectionId,
        '\$databaseId': current[idx].$databaseId,
        '\$createdAt': current[idx].$createdAt,
        '\$updatedAt': DateTime.now().toIso8601String(),
        '\$permissions': current[idx].$permissions,
        ...current[idx].data,
        ...payload,
      };
      current[idx] = models.Document.fromMap(merged);
      await _cacheList(key, current);
    }
  }

  String _chantiersCacheKey(String userId, String role) =>
      'pump_cache_chantiers_${role}_$userId';
  String _canalisationsCacheKey(String chantierId) =>
      'pump_cache_canalisations_$chantierId';

  // ─────────────────────────────────────────────
  // FILE D'ATTENTE D'ÉCRITURES HORS-LIGNE
  // ─────────────────────────────────────────────

  static const _queueKey = 'pump_pending_ops';
  static const _mappingKey = 'pump_id_mapping'; // tempId -> vrai ID Appwrite

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  Future<void> _queueOp(Map<String, dynamic> op) async {
    final queue = await _loadQueue();
    queue.add(op);
    await _saveQueue(queue);
  }

  Future<Map<String, String>> _loadMapping() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mappingKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  Future<void> _saveMapping(Map<String, String> mapping) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mappingKey, jsonEncode(mapping));
  }

  String _newTempId() =>
      'local_${DateTime.now().millisecondsSinceEpoch}_${identityHashCode(this)}';

  /// Nombre d'opérations en attente de synchronisation (à afficher dans l'UI,
  /// ex : badge "3 modifications non synchronisées").
  Future<int> pendingCount() async => (await _loadQueue()).length;

  /// Rejoue la file d'attente vers Appwrite. À appeler au retour du réseau
  /// (ex : listener de connectivité dans main.dart, ou pull-to-refresh).
  Future<void> syncPendingOperations() async {
    if (!await _isOnline()) return;

    final queue = await _loadQueue();
    if (queue.isEmpty) return;

    final mapping = await _loadMapping();
    final remaining = <Map<String, dynamic>>[];

    for (final op in queue) {
      try {
        final type = op['type'] as String;
        final data = Map<String, dynamic>.from(op['data'] as Map);

        // Remplace toute référence à un ID temporaire par le vrai ID
        // Appwrite, une fois que le parent a été synchronisé.
        for (final field in ['chantierID', 'docId']) {
          if (data[field] != null && mapping.containsKey(data[field])) {
            data[field] = mapping[data[field]];
          }
        }

        switch (type) {
          case 'createChantier':
            final created = await _db.createDocument(
              databaseId: databaseId, collectionId: chantiersTable,
              documentId: ID.unique(), data: data['payload']);
            mapping[op['tempId'] as String] = created.$id;
            break;

          case 'createCanalisation':
            final created = await _db.createDocument(
              databaseId: databaseId, collectionId: canalisationsTable,
              documentId: ID.unique(), data: data['payload']);
            mapping[op['tempId'] as String] = created.$id;
            break;

          case 'updateChantier':
          case 'updateChantierParams':
          case 'updateCanalisation':
            final docId = mapping[data['docId']] ?? data['docId'] as String;
            // Un document créé hors-ligne et pas encore synchronisé :
            // on garde cette opération en attente pour le prochain passage.
            if (docId.toString().startsWith('local_')) {
              remaining.add(op);
              continue;
            }
            final collection = type == 'updateCanalisation'
                ? canalisationsTable : chantiersTable;
            await _db.updateDocument(
              databaseId: databaseId, collectionId: collection,
              documentId: docId, data: data['payload']);
            break;

          case 'deleteChantier':
          case 'deleteCanalisation':
            final docId = mapping[data['docId']] ?? data['docId'] as String;
            if (docId.toString().startsWith('local_')) {
              // Jamais synchronisé, jamais existé côté serveur : on l'annule
              // simplement, pas besoin de le rejouer.
              continue;
            }
            final collection = type == 'deleteCanalisation'
                ? canalisationsTable : chantiersTable;
            await _db.deleteDocument(
              databaseId: databaseId, collectionId: collection,
              documentId: docId);
            break;
        }
      } catch (e) {
        // Échec réseau ponctuel : on la garde pour le prochain essai.
        remaining.add(op);
      }
    }

    await _saveMapping(mapping);
    await _saveQueue(remaining);
  }

  // ── Chantiers ──────────────────────────────────
  Future<List<models.Document>> getChantiers(String userId, String role) async {
    final cacheKey = _chantiersCacheKey(userId, role);

    if (await _isOnline()) {
      // Pousse d'abord tout ce qui est en attente — sinon une lecture
      // fraîche ici pourrait récupérer une version obsolète côté serveur
      // et écraser le cache local à jour avec des données périmées.
      await syncPendingOperations();
      try {
        final queries = (role == 'super_admin' || role == 'admin')
          ? <String>[] : [Query.equal('userID', userId)];
        final result = await _db.listDocuments(
          databaseId: databaseId, collectionId: chantiersTable, queries: queries);
        // Filet de sécurité : si un document créé hors-ligne n'a malgré
        // tout pas encore été synchronisé (ex: la sync ci-dessus a
        // échoué), on ne le perd pas de vue — on le garde affiché en
        // plus des résultats serveur, en attendant le prochain essai.
        final previouslyCached = await _readCachedList(cacheKey);
        final stillPendingLocal =
            previouslyCached.where((d) => d.$id.startsWith('local_'));
        final merged = [...result.documents, ...stillPendingLocal];
        await _cacheList(cacheKey, merged);
        return merged;
      } catch (e) {
        return _readCachedList(cacheKey);
      }
    }
    return _readCachedList(cacheKey);
  }

  Future<models.Document> createChantier({
    required String nom, required String ville, required String rue,
    required String batiment, required String date,
    required String userId, required String company,
    required String resinType, required String epaisseur,
    required int desiredPasses,
  }) async {
    final payload = {
      'nom': nom, 'ville': ville, 'rue': rue, 'batiment': batiment,
      'date': date, 'userID': userId, 'company': company,
      'resinType': resinType, 'epaisseur': epaisseur,
      'desiredPasses': desiredPasses,
    };

    if (await _isOnline()) {
      final doc = await _db.createDocument(
        databaseId: databaseId, collectionId: chantiersTable,
        documentId: ID.unique(), data: payload);
      await _upsertInCache(_chantiersCacheKey(userId, 'admin'), doc);
      return doc;
    }

    // ── Hors ligne : création locale optimiste ──
    final tempId = _newTempId();
    final localDoc = models.Document.fromMap({
      '\$id': tempId,
      '\$collectionId': chantiersTable,
      '\$databaseId': databaseId,
      '\$createdAt': DateTime.now().toIso8601String(),
      '\$updatedAt': DateTime.now().toIso8601String(),
      '\$permissions': [],
      ...payload,
    });
    await _upsertInCache(_chantiersCacheKey(userId, 'admin'), localDoc);
    await _queueOp({
      'type': 'createChantier',
      'tempId': tempId,
      'data': {'payload': payload},
    });
    return localDoc;
  }

  Future<void> updateChantierParams(String docId,
      String resinType, String epaisseur, int desiredPasses) async {
    final payload = {'resinType': resinType, 'epaisseur': epaisseur,
                      'desiredPasses': desiredPasses};
    if (await _isOnline()) {
      await _db.updateDocument(
        databaseId: databaseId, collectionId: chantiersTable,
        documentId: docId, data: payload);
      return;
    }
    await _updateIdInCachesWithPrefix('pump_cache_chantiers_', docId, payload);
    await _queueOp({
      'type': 'updateChantierParams',
      'data': {'docId': docId, 'payload': payload},
    });
  }

  Future<void> updateChantier(String docId, {
    required String nom, required String ville,
    required String rue, required String batiment,
    required String date,
  }) async {
    final payload = {'nom': nom, 'ville': ville, 'rue': rue,
                      'batiment': batiment, 'date': date};
    if (await _isOnline()) {
      await _db.updateDocument(
        databaseId: databaseId, collectionId: chantiersTable,
        documentId: docId, data: payload);
      return;
    }
    await _updateIdInCachesWithPrefix('pump_cache_chantiers_', docId, payload);
    await _queueOp({
      'type': 'updateChantier',
      'data': {'docId': docId, 'payload': payload},
    });
  }

  Future<void> deleteChantier(String docId) async {
    await _removeIdFromCachesWithPrefix('pump_cache_chantiers_', docId);
    if (await _isOnline()) {
      await _db.deleteDocument(databaseId: databaseId,
        collectionId: chantiersTable, documentId: docId);
      return;
    }
    await _queueOp({
      'type': 'deleteChantier',
      'data': {'docId': docId},
    });
  }

  // ── Canalisations ──────────────────────────────
  Future<List<models.Document>> getCanalisations(String chantierId) async {
    final cacheKey = _canalisationsCacheKey(chantierId);

    if (await _isOnline()) {
      // Même précaution que getChantiers : on vide la file d'attente
      // avant de lire, sinon on risque d'écraser le cache local à jour
      // (ex: passesDone après une passe) avec une version serveur pas
      // encore rafraîchie.
      await syncPendingOperations();
      try {
        final result = await _db.listDocuments(
          databaseId: databaseId, collectionId: canalisationsTable,
          queries: [Query.equal('chantierID', chantierId)]);
        // Filet de sécurité : une canalisation créée hors-ligne pas
        // encore synchronisée ne doit jamais disparaître de la liste.
        final previouslyCached = await _readCachedList(cacheKey);
        final stillPendingLocal =
            previouslyCached.where((d) => d.$id.startsWith('local_'));
        final merged = [...result.documents, ...stillPendingLocal];
        await _cacheList(cacheKey, merged);
        return merged;
      } catch (e) {
        return _readCachedList(cacheKey);
      }
    }
    return _readCachedList(cacheKey);
  }

  /// Récupère une seule canalisation par ID (cherche dans la liste du
  /// chantier). Utile pour rafraîchir une donnée précise (ex: passesData)
  /// sans re-télécharger/écraser tout le cache d'un coup.
  Future<models.Document?> getCanalisationById(
      String chantierId, String docId) async {
    final list = await getCanalisations(chantierId);
    for (final d in list) {
      if (d.$id == docId) return d;
    }
    return null;
  }

  Future<models.Document> createCanalisation({
    required String chantierId, required String label,
    required String longueur, required String diametre,
    required int passes, required String userId,
  }) async {
    final payload = {
      'chantierID': chantierId, 'label': label,
      'longueur': longueur, 'diametre': diametre,
      'passes': passes, 'statut': 'en_attente', 'userID': userId,
      'passesDone': 0,
    };

    if (await _isOnline()) {
      final doc = await _db.createDocument(
        databaseId: databaseId, collectionId: canalisationsTable,
        documentId: ID.unique(), data: payload);
      await _upsertInCache(_canalisationsCacheKey(chantierId), doc);
      return doc;
    }

    // ── Hors ligne : création locale optimiste ──
    final tempId = _newTempId();
    final localDoc = models.Document.fromMap({
      '\$id': tempId,
      '\$collectionId': canalisationsTable,
      '\$databaseId': databaseId,
      '\$createdAt': DateTime.now().toIso8601String(),
      '\$updatedAt': DateTime.now().toIso8601String(),
      '\$permissions': [],
      ...payload,
    });
    await _upsertInCache(_canalisationsCacheKey(chantierId), localDoc);
    await _queueOp({
      'type': 'createCanalisation',
      'tempId': tempId,
      'data': {'payload': payload},
    });
    return localDoc;
  }

  Future<void> updateCanalisation(String docId, {
    String? label, String? longueur, String? diametre,
    int? passes, String? statut, int? passesDone,
    String? passesData, double? resinAppliedTotal,
  }) async {
    final payload = <String, dynamic>{};
    if (label      != null) payload['label']      = label;
    if (longueur   != null) payload['longueur']   = longueur;
    if (diametre   != null) payload['diametre']   = diametre;
    if (passes     != null) payload['passes']     = passes;
    if (statut     != null) payload['statut']     = statut;
    if (passesDone != null) payload['passesDone'] = passesDone;
    if (passesData != null) payload['passesData'] = passesData;
    if (resinAppliedTotal != null) payload['resinAppliedTotal'] = resinAppliedTotal;

    if (await _isOnline()) {
      await _db.updateDocument(databaseId: databaseId,
        collectionId: canalisationsTable, documentId: docId, data: payload);
      return;
    }
    // Hors ligne : applique tout de suite en local (visible immédiatement
    // dans l'app, ex: passesDone après une passe), en plus de la mise en
    // file d'attente pour la synchronisation ultérieure vers Appwrite.
    await _updateIdInCachesWithPrefix(
        'pump_cache_canalisations_', docId, payload);
    await _queueOp({
      'type': 'updateCanalisation',
      'data': {'docId': docId, 'payload': payload},
    });
  }

  Future<void> deleteCanalisation(String docId) async {
    await _removeIdFromCachesWithPrefix('pump_cache_canalisations_', docId);
    if (await _isOnline()) {
      await _db.deleteDocument(databaseId: databaseId,
        collectionId: canalisationsTable, documentId: docId);
      return;
    }
    await _queueOp({
      'type': 'deleteCanalisation',
      'data': {'docId': docId},
    });
  }
}