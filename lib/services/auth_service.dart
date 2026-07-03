import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_roles.dart';

class AuthService {
  static const String endpoint    = 'https://cloud.appwrite.io/v1';
  static const String projectId   = '69ccd61d0017c7eaedee';
  static const String databaseId  = '69cd0f11001c948b59e9';
  static const String rolesTable  = 'users_roles';

  late Client    _client;
  late Account   _account;
  late Databases _db;

  AuthService() {
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    _account = Account(_client);
    _db      = Databases(_client);
  }

  // ─────────────────────────────────────────────
  // AUTH DE BASE
  // ─────────────────────────────────────────────

  Future<models.Session> login(String email, String password) async {
    final session = await _account.createEmailPasswordSession(
      email: email,
      password: password,
    );
    final user = await _account.get();
    await _cacheSession(user);
    return session;
  }

  Future<models.User?> getCurrentUser() async {
    try {
      return await _account.get()
        .timeout(const Duration(seconds: 4));
    } catch (e) {
      return null;
    }
  }

  Future<void> logout() async {
    await _account.deleteSession(sessionId: 'current');
    await clearCachedSession();
  }

  // ─────────────────────────────────────────────
  // SESSION HORS LIGNE
  // ─────────────────────────────────────────────

  /// Sauvegarde les infos de session après une connexion réussie en ligne
  Future<void> _cacheSession(models.User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_user_id', user.$id);
    await prefs.setString('cached_user_email', user.email);
    await prefs.setString('cached_user_name', user.name);
    await prefs.setBool('has_valid_session', true);
  }

  /// Vérifie s'il existe une session mise en cache (pour mode hors ligne)
  Future<Map<String, String>?> getCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSession = prefs.getBool('has_valid_session') ?? false;
    if (!hasSession) return null;

    final userId = prefs.getString('cached_user_id');
    final email  = prefs.getString('cached_user_email');
    final name   = prefs.getString('cached_user_name');
    if (userId == null || email == null) return null;

    return {
      'userId': userId,
      'email' : email,
      'name'  : name ?? '',
    };
  }

  /// Cache les données rôle/statut/produits pour lecture hors ligne
  Future<void> cacheUserData({
    required String role,
    required String status,
    required List<String> products,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_role', role);
    await prefs.setString('cached_status', status);
    await prefs.setString('cached_products', products.join(','));
  }

  Future<Map<String, dynamic>> getCachedUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final products = prefs.getString('cached_products') ?? '';
    return {
      'role'    : prefs.getString('cached_role') ?? AppRoles.entreprise,
      'status'  : prefs.getString('cached_status') ?? AppRoles.statusActive,
      'products': products.isEmpty ? <String>[] : products.split(','),
    };
  }

  /// Efface la session en cache (à la déconnexion)
  Future<void> clearCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user_id');
    await prefs.remove('cached_user_email');
    await prefs.remove('cached_user_name');
    await prefs.remove('has_valid_session');
    await prefs.remove('cached_role');
    await prefs.remove('cached_status');
    await prefs.remove('cached_products');
  }

  // ─────────────────────────────────────────────
  // INSCRIPTION
  // ─────────────────────────────────────────────

  Future<models.User> registerEntreprise({
    required String email,
    required String password,
    required String name,
    required String company,
    required String distributorId,
    required String distributorEmail,
    String country  = '',
    String reseller = '',
  }) async {
    final user = await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );

    await _db.createDocument(
      databaseId: databaseId,
      collectionId: rolesTable,
      documentId: ID.unique(),
      data: {
        'userID'         : user.$id,
        'role'           : AppRoles.entreprise,
        'name'           : name,
        'email'          : email,
        'company'        : company,
        'distributor_id' : distributorId,
        'company_id'     : '',
        'products'       : '',
        'status'         : AppRoles.statusPending,
        'country'        : country,
        'reseller'       : reseller,
      },
    );

    await _sendEmailToDistributor(
      distributorEmail : distributorEmail,
      enterpriseName   : name,
      enterpriseEmail  : email,
      company          : company,
    );

    return user;
  }

  Future<models.User> registerEmploye({
    required String email,
    required String password,
    required String name,
    required String companyId,
    required String companyEmail,
  }) async {
    final user = await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );

    await _db.createDocument(
      databaseId: databaseId,
      collectionId: rolesTable,
      documentId: ID.unique(),
      data: {
        'userID'         : user.$id,
        'role'           : AppRoles.employe,
        'name'           : name,
        'email'          : email,
        'company'        : '',
        'distributor_id' : '',
        'company_id'     : companyId,
        'products'       : '',
        'status'         : AppRoles.statusPending,
      },
    );

    await _sendEmailToEntreprise(
      entrepriseEmail : companyEmail,
      employeName     : name,
      employeEmail    : email,
    );

    return user;
  }

  Future<models.User> register(
    String email,
    String password,
    String name,
    String company,
  ) async {
    return await registerEntreprise(
      email            : email,
      password         : password,
      name             : name,
      company          : company,
      distributorId    : '',
      distributorEmail : '',
    );
  }

  // ─────────────────────────────────────────────
  // VALIDATION DE COMPTE
  // ─────────────────────────────────────────────

  Future<void> validerCompte({
    required String documentId,
    required String userEmail,
    required String userName,
    required List<String> products,
  }) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: rolesTable,
      documentId  : documentId,
      data        : {
        'status'  : AppRoles.statusActive,
        'products': products.join(','),
      },
    );

    await _sendConfirmationEmail(
      userEmail : userEmail,
      userName  : userName,
      products  : products,
    );
  }

  Future<void> suspendreCompte(String documentId) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: rolesTable,
      documentId  : documentId,
      data        : {'status': AppRoles.statusSuspended},
    );
  }

  // ─────────────────────────────────────────────
  // RÉCUPÉRATION DES DONNÉES
  // ─────────────────────────────────────────────

  Future<String> getUserRole(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      ).timeout(const Duration(seconds: 4));
      if (result.documents.isNotEmpty) {
        return result.documents.first.data['role'] ?? AppRoles.entreprise;
      }
    } catch (e) { /* ignore */ }
    return AppRoles.entreprise;
  }

  Future<String> getUserStatus(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) {
        return result.documents.first.data['status'] ?? AppRoles.statusPending;
      }
    } catch (e) { /* ignore */ }
    return AppRoles.statusPending;
  }

  Future<Map<String, dynamic>?> getUserRoleData(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) {
        return result.documents.first.data;
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  Future<List<models.Document>> getPendingComptes({
    String? distributorId,
  }) async {
    try {
      final queries = [Query.equal('status', AppRoles.statusPending)];
      if (distributorId != null && distributorId.isNotEmpty) {
        queries.add(Query.equal('distributor_id', distributorId));
      }
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : queries,
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  Future<List<models.Document>> getEntreprisesByDistributeur(
    String distributorId,
  ) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [
          Query.equal('distributor_id', distributorId),
          Query.equal('role', AppRoles.entreprise),
        ],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  Future<List<models.Document>> getEmployesByEntreprise(
    String companyId,
  ) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [
          Query.equal('company_id', companyId),
          Query.equal('role', AppRoles.employe),
        ],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  Future<List<models.Document>> getAllUsersRoles() async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  Future<List<models.Document>> getDistributeurs() async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('role', AppRoles.distributeur)],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  // ── Trouve le distributeur par pays, fallback Picote ──────────────────────
  static const String _picoteEmail = 'distributeur@picote.com'; // ← à changer

  Future<Map<String, String>> getDistributeurByCountry(String country) async {
    try {
      // France → toujours Robocana
      if (country.toLowerCase() == 'france') {
        final result = await _db.listDocuments(
          databaseId  : databaseId,
          collectionId: rolesTable,
          queries     : [
            Query.equal('role', AppRoles.distributeur),
            Query.search('name', 'Robocana'),
          ],
        );
        if (result.documents.isNotEmpty) {
          final doc = result.documents.first;
          return {
            'id':    doc.$id,
            'email': doc.data['email'] ?? '',
          };
        }
      }

      // Autres pays → cherche un distributeur avec ce pays
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [
          Query.equal('role', AppRoles.distributeur),
          Query.equal('country', country),
        ],
      );
      if (result.documents.isNotEmpty) {
        final doc = result.documents.first;
        return {
          'id':    doc.$id,
          'email': doc.data['email'] ?? '',
        };
      }
    } catch (e) { /* ignore */ }

    // Fallback → Picote
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [
          Query.equal('role', AppRoles.distributeur),
          Query.equal('email', _picoteEmail),
        ],
      );
      if (result.documents.isNotEmpty) {
        final doc = result.documents.first;
        return {
          'id':    doc.$id,
          'email': doc.data['email'] ?? '',
        };
      }
    } catch (e) { /* ignore */ }

    // Aucun distributeur trouvé
    return {'id': '', 'email': ''};
  }

  // ─────────────────────────────────────────────
  // MISES À JOUR
  // ─────────────────────────────────────────────

  Future<void> updateRole(String documentId, String newRole) async {
    await _db.updateDocument(
      databaseId  : databaseId,
      collectionId: rolesTable,
      documentId  : documentId,
      data        : {'role': newRole},
    );
  }

  Future<void> updateUserProducts(
    String userId,
    List<String> products,
  ) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) {
        await _db.updateDocument(
          databaseId  : databaseId,
          collectionId: rolesTable,
          documentId  : result.documents.first.$id,
          data        : {'products': products.join(',')},
        );
      }
    } catch (e) { /* ignore */ }
  }

  Future<List<String>> getUserProducts(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) {
        final p = result.documents.first.data['products'] as String? ?? '';
        return p.isEmpty ? [] : p.split(',');
      }
    } catch (e) { /* ignore */ }
    return [];
  }

  Future<String> getUserReseller(String userId) async {
    final data = await getUserRoleData(userId);
    return data?['reseller'] as String? ?? '';
  }

  // ── Récupérer l'email du distributeur de l'utilisateur ────────────────────
  Future<String> getDistributeurEmail(String userId) async {
    try {
      final data = await getUserRoleData(userId);
      if (data == null) return _picoteEmail;
      final distributorId = data['distributor_id'] as String? ?? '';
      if (distributorId.isEmpty) return _picoteEmail;
      // Chercher le distributeur par son userID
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [
          Query.equal('userID', distributorId),
          Query.equal('role', AppRoles.distributeur),
        ],
      );
      if (result.documents.isNotEmpty) {
        return result.documents.first.data['email'] as String? ?? _picoteEmail;
      }
      return _picoteEmail;
    } catch (e) {
      return _picoteEmail;
    }
  }

  Future<String> getUserCompany(String userId) async {
    try {
      final result = await _db.listDocuments(
        databaseId  : databaseId,
        collectionId: rolesTable,
        queries     : [Query.equal('userID', userId)],
      );
      if (result.documents.isNotEmpty) {
        return result.documents.first.data['company'] ?? '';
      }
    } catch (e) { /* ignore */ }
    return '';
  }

  Future<void> updateName(String name) async {
    await _account.updateName(name: name);
  }

  Future<void> updatePassword(String newPassword) async {
    await _account.updatePassword(password: newPassword);
  }

  // ─────────────────────────────────────────────
  // EMAILS — via Appwrite Functions (Resend)
  // Note : Messaging.createEmail n'est pas disponible
  // côté client dans le SDK Flutter Appwrite 23.x
  // Les emails sont donc déclenchés via une Function
  // Appwrite qui sera créée ultérieurement.
  // En attendant, les appels échouent silencieusement
  // sans bloquer l'inscription ni la validation.
  // ─────────────────────────────────────────────

  Future<void> _sendEmailToDistributor({
    required String distributorEmail,
    required String enterpriseName,
    required String enterpriseEmail,
    required String company,
  }) async {
    if (distributorEmail.isEmpty) return;
    try {
      final functions = Functions(_client);
      await functions.createExecution(
        functionId : 'send-email',
        body       : 'to=$distributorEmail'
            '&subject=Nouvelle entreprise en attente de validation'
            '&body=Nom: $enterpriseName | Entreprise: $company | Email: $enterpriseEmail',
      );
    } catch (e) { /* ignore — ne bloque pas l'inscription */ }
  }

  Future<void> _sendEmailToEntreprise({
    required String entrepriseEmail,
    required String employeName,
    required String employeEmail,
  }) async {
    if (entrepriseEmail.isEmpty) return;
    try {
      final functions = Functions(_client);
      await functions.createExecution(
        functionId : 'send-email',
        body       : 'to=$entrepriseEmail'
            '&subject=Nouvel employé en attente de validation'
            '&body=Nom: $employeName | Email: $employeEmail',
      );
    } catch (e) { /* ignore */ }
  }

  Future<void> _sendConfirmationEmail({
    required String userEmail,
    required String userName,
    required List<String> products,
  }) async {
    if (userEmail.isEmpty) return;
    try {
      final functions = Functions(_client);
      await functions.createExecution(
        functionId : 'send-email',
        body       : 'to=$userEmail'
            '&subject=Votre compte BZBots Suite est activé'
            '&body=Bonjour $userName | Modules: ${products.join(", ")}',
      );
    } catch (e) { /* ignore */ }
  }
}