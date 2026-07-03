// lib/services/app_roles.dart

class AppRoles {
  // ─── Constantes des rôles ───────────────────────────────────────
  static const String superAdmin   = 'super_admin';
  static const String admin        = 'admin';
  static const String distributeur = 'distributeur';
  static const String entreprise   = 'entreprise';
  static const String employe      = 'employe';

  // ─── Hiérarchie (plus l'index est bas, plus le rôle est élevé) ──
  static const List<String> hierarchy = [
    superAdmin,
    admin,
    distributeur,
    entreprise,
    employe,
  ];

  // ─── Statuts de compte ──────────────────────────────────────────
  static const String statusPending   = 'pending';
  static const String statusActive    = 'active';
  static const String statusSuspended = 'suspended';

  // ─── Vérifications de rôle ──────────────────────────────────────
  static bool isSuperAdmin(String role)   => role == superAdmin;
  static bool isAdmin(String role)        => role == admin;
  static bool isDistributeur(String role) => role == distributeur;
  static bool isEntreprise(String role)   => role == entreprise;
  static bool isEmploye(String role)      => role == employe;

  /// Vérifie si [role] est au moins aussi élevé que [minimum]
  static bool hasMinimumRole(String role, String minimum) {
    final userIndex    = hierarchy.indexOf(role);
    final minimumIndex = hierarchy.indexOf(minimum);
    if (userIndex == -1 || minimumIndex == -1) return false;
    return userIndex <= minimumIndex;
  }

  // ─── Permissions ────────────────────────────────────────────────

  /// Peut créer / élever un compte admin
  static bool canManageAdmins(String role) =>
      isSuperAdmin(role);

  /// Peut créer / élever un compte distributeur
  static bool canManageDistributeurs(String role) =>
      hasMinimumRole(role, admin);

  /// Peut valider un compte entreprise (pending → active)
  static bool canValiderEntreprise(String role) =>
      hasMinimumRole(role, distributeur);

  /// Peut valider un compte employé
  static bool canValiderEmploye(String role) =>
      isEntreprise(role) || hasMinimumRole(role, admin);

  /// Peut assigner des products à un compte
  static bool canAssignProducts(String role) =>
      hasMinimumRole(role, distributeur);

  /// Peut voir le panel d'administration
  static bool canAccessAdminPanel(String role) =>
      hasMinimumRole(role, admin);

  /// Peut voir le panel distributeur
  static bool canAccessDistributeurPanel(String role) =>
      hasMinimumRole(role, distributeur);

  /// Peut créer un chantier
  static bool canCreateChantier(String role) =>
      isEntreprise(role) || hasMinimumRole(role, admin);

  /// Peut voir les chantiers
  static bool canViewChantiers(String role) =>
      hasMinimumRole(role, employe);

  // ─── Rôles disponibles à l'inscription ─────────────────────────
  /// Rôles que l'utilisateur peut choisir librement à l'inscription
  static const List<String> registerableRoles = [
    entreprise,
    employe,
  ];

  // ─── Rôles nécessitant validation ───────────────────────────────
  static bool requiresValidation(String role) =>
      role == entreprise || role == employe;

  // ─── Label lisible par rôle ─────────────────────────────────────
  static String label(String role) {
    switch (role) {
      case superAdmin:   return 'Super Administrateur';
      case admin:        return 'Administrateur';
      case distributeur: return 'Distributeur';
      case entreprise:   return 'Entreprise';
      case employe:      return 'Employé';
      default:           return 'Inconnu';
    }
  }

  // ─── Couleur associée au rôle (pour badges UI) ──────────────────
  static int roleColor(String role) {
    switch (role) {
      case superAdmin:   return 0xFFE53935; // rouge
      case admin:        return 0xFFFF6F00; // orange
      case distributeur: return 0xFF1E88E5; // bleu
      case entreprise:   return 0xFF43A047; // vert
      case employe:      return 0xFF8E24AA; // violet
      default:           return 0xFF9E9E9E; // gris
    }
  }
  // Liste complète des rôles (pour les dropdowns)
static const List<String> all = [
  superAdmin, admin, distributeur, entreprise, employe,
];

// Alias pour compatibilité avec l'ancien code
static int color(String role) => roleColor(role);
/// Vérifie si l'utilisateur peut accéder à un module
static bool canAccess(String role, String module, {List<String> products = const []}) {
  // super_admin et admin ont accès à tout
  if (hasMinimumRole(role, admin)) return true;
  // Les autres vérifient leurs products
  return products.contains(module);
  }
}