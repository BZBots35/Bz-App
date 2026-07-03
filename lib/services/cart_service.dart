// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

class CartItem {
  final String id;
  final String name;
  final String version;
  final String robotSerial;
  final String img;
  int qty;

  CartItem({
    required this.id,
    required this.name,
    required this.version,
    required this.robotSerial,
    this.img = '',
    this.qty = 1,
  });

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    'version':     version,
    'robotSerial': robotSerial,
    'img':         img,
    'qty':         qty,
  };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
    id:          j['id'] as String,
    name:        j['name'] as String,
    version:     j['version'] as String? ?? '',
    robotSerial: j['robotSerial'] as String,
    img:         j['img'] as String? ?? '',
    qty:         j['qty'] as int? ?? 1,
  );
}

class CartService {
  static const String endpoint    = 'https://cloud.appwrite.io/v1';
  static const String projectId   = '69ccd61d0017c7eaedee';
  static const String databaseId  = '69cd0f11001c948b59e9';
  static const String cartsTable  = 'carts';

  late Client    _client;
  late Databases _db;

  CartService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _db = Databases(_client);
  }

  // ── Récupérer ou créer le document panier de l'utilisateur ───────────────
  Future<models.Document?> _getCartDoc(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId: databaseId,
        collectionId: cartsTable,
        queries: [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) return result.documents.first;
    } catch (e) { /* ignore */ }
    return null;
  }

  // ── Lire le panier ────────────────────────────────────────────────────────
  Future<List<CartItem>> getCart(String userId) async {
    try {
      final doc = await _getCartDoc(userId);
      if (doc == null) return [];
      final raw = doc.data['items'] as String? ?? '';
      if (raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  // ── Nombre d'articles total ───────────────────────────────────────────────
  Future<int> getCartCount(String userId) async {
    final items = await getCart(userId);
    return items.fold<int>(0, (sum, item) => sum + item.qty);
  }

  // ── Sauvegarder le panier ─────────────────────────────────────────────────
  Future<void> _saveCart(String userId, List<CartItem> items) async {
    print('=== _saveCart: userId=$userId items=${items.length}');
    try {
      final now  = DateTime.now().toIso8601String();
      final data = {
        'userID':    userId,
        'items':     jsonEncode(items.map((e) => e.toJson()).toList()),
        'updatedAt': now,
      };
      final doc = await _getCartDoc(userId);
      if (doc == null) {
        print('=== création nouveau document panier');
        await _db.createDocument(
          databaseId: databaseId,
          collectionId: cartsTable,
          documentId: ID.unique(),
          data: data,
        );
      } else {
        print('=== mise à jour document panier: ${doc.$id}');
        await _db.updateDocument(
          databaseId: databaseId,
          collectionId: cartsTable,
          documentId: doc.$id,
          data: data,
        );
      }
      print('=== _saveCart OK');
    } catch (e) {
      print('=== ERREUR _saveCart: $e');
    }
  }

  // ── Ajouter un article ────────────────────────────────────────────────────
  Future<void> addItem(String userId, CartItem newItem) async {
    print('=== addItem: userId=$userId item=${newItem.id} robot=${newItem.robotSerial}');
    try {
      final items = await getCart(userId);
      print('=== panier actuel: ${items.length} items');
      final existing = items.indexWhere(
        (e) => e.id == newItem.id && e.robotSerial == newItem.robotSerial);
      if (existing >= 0) {
        items[existing].qty += 1;
        print('=== article existant, qty: ${items[existing].qty}');
      } else {
        items.add(newItem);
        print('=== nouvel article ajouté');
      }
      await _saveCart(userId, items);
      print('=== sauvegarde OK');
    } catch (e) {
      print('=== ERREUR addItem: $e');
    }
  }

  // ── Modifier la quantité ──────────────────────────────────────────────────
  Future<void> updateQty(String userId, String itemId, String robotSerial, int qty) async {
    final items = await getCart(userId);
    final idx = items.indexWhere(
      (e) => e.id == itemId && e.robotSerial == robotSerial);
    if (idx >= 0) {
      if (qty <= 0) {
        items.removeAt(idx);
      } else {
        items[idx].qty = qty;
      }
    }
    await _saveCart(userId, items);
  }

  // ── Supprimer un article ──────────────────────────────────────────────────
  Future<void> removeItem(String userId, String itemId, String robotSerial) async {
    final items = await getCart(userId);
    items.removeWhere((e) => e.id == itemId && e.robotSerial == robotSerial);
    await _saveCart(userId, items);
  }

  // ── Vider le panier ───────────────────────────────────────────────────────
  Future<void> clearCart(String userId) async {
    await _saveCart(userId, []);
  }
}
