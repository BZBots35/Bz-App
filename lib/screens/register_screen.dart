// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl         = TextEditingController();
  final _companyCtrl      = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passCtrl         = TextEditingController();
  final _confirmCtrl      = TextEditingController();
  final _entrepriseCtrl   = TextEditingController();
  final _auth             = AuthService();
  final _lang             = LangService();

  bool _loading           = false;
  bool _showPass          = false;
  String? _error;
  String? _selectedCountry;
  String? _selectedReseller;

  // Rôle sélectionné par l'utilisateur
  String _selectedRole    = AppRoles.entreprise;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _register() async {
    // ── Validations communes ──────────────────────
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '${_lang.t("firstName")} requis'); return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = '${_lang.t("email")} requis'); return;
    }
    if (_passCtrl.text.length < 8) {
      setState(() => _error = 'Minimum 8 caractères'); return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas'); return;
    }

    // ── Validations par rôle ──────────────────────
    if (_selectedRole == AppRoles.entreprise) {
      if (_companyCtrl.text.trim().isEmpty) {
        setState(() => _error = '${_lang.t("company")} requis'); return;
      }
      if (_selectedCountry == null) {
        setState(() => _error = 'Veuillez sélectionner votre pays'); return;
      }
      if (_selectedReseller == null) {
        setState(() => _error = 'Veuillez sélectionner votre revendeur'); return;
      }
    }
    if (_selectedRole == AppRoles.employe) {
      if (_entrepriseCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Veuillez renseigner votre entreprise'); return;
      }
    }

    setState(() { _loading = true; _error = null; });

    try {
      if (_selectedRole == AppRoles.entreprise) {
        // Trouve automatiquement le distributeur selon le pays
        final distrib = await _auth.getDistributeurByCountry(_selectedCountry!);
        await _auth.registerEntreprise(
          email            : _emailCtrl.text.trim(),
          password         : _passCtrl.text.trim(),
          name             : _nameCtrl.text.trim(),
          company          : _companyCtrl.text.trim(),
          distributorId    : distrib['id'] ?? '',
          distributorEmail : distrib['email'] ?? '',
          country          : _selectedCountry ?? '',
          reseller         : _selectedReseller ?? '',
        );
      } else {
        await _auth.registerEmploye(
          email        : _emailCtrl.text.trim(),
          password     : _passCtrl.text.trim(),
          name         : _nameCtrl.text.trim(),
          companyId    : _entrepriseCtrl.text.trim(),
          companyEmail : '',
        );
      }

      // Connexion automatique
      await _auth.login(_emailCtrl.text.trim(), _passCtrl.text.trim());

      if (mounted) {
        // Redirection vers écran d'attente de validation
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PendingScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() => _error = 'Erreur — email déjà utilisé ?');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _entrepriseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 40),

            // ── Header ──────────────────────────────
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: const Icon(Icons.chevron_left, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Text(_lang.t('createAccount'),
                style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 40),

            Align(alignment: Alignment.centerLeft,
              child: Text(_lang.t('register'),
                style: TextStyle(color: Colors.grey[400], fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 3))),
            const SizedBox(height: 20),

            // ── Sélection du rôle ────────────────────
            _SectionLabel(label: 'TYPE DE COMPTE'),
            const SizedBox(height: 10),
            Row(children: [
              _RoleChip(
                label    : 'Entreprise',
                icon     : Icons.business_outlined,
                selected : _selectedRole == AppRoles.entreprise,
                color    : const Color(0xFF43A047),
                onTap    : () => setState(() => _selectedRole = AppRoles.entreprise),
              ),
              const SizedBox(width: 10),
              _RoleChip(
                label    : 'Employé',
                icon     : Icons.badge_outlined,
                selected : _selectedRole == AppRoles.employe,
                color    : const Color(0xFF8E24AA),
                onTap    : () => setState(() => _selectedRole = AppRoles.employe),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Champs communs ───────────────────────
            _SectionLabel(label: 'INFORMATIONS'),
            const SizedBox(height: 10),
            _InputField(
              controller   : _nameCtrl,
              label        : _lang.t('firstName'),
              icon         : Icons.person_outline),
            const SizedBox(height: 14),
            _InputField(
              controller   : _emailCtrl,
              label        : _lang.t('email'),
              icon         : Icons.email_outlined,
              keyboardType : TextInputType.emailAddress),
            const SizedBox(height: 14),
            _InputField(
              controller : _passCtrl,
              label      : _lang.t('password'),
              icon       : Icons.lock_outline,
              obscure    : !_showPass,
              suffix     : IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600], size: 18),
                onPressed: () => setState(() => _showPass = !_showPass))),
            const SizedBox(height: 14),
            _InputField(
              controller : _confirmCtrl,
              label      : _lang.t('confirmPass'),
              icon       : Icons.lock_outline,
              obscure    : !_showPass),
            const SizedBox(height: 24),

            // ── Champs ENTREPRISE ────────────────────
            if (_selectedRole == AppRoles.entreprise) ...[
              _SectionLabel(label: 'VOTRE ENTREPRISE'),
              const SizedBox(height: 10),
              _InputField(
                controller : _companyCtrl,
                label      : _lang.t('company'),
                icon       : Icons.business_outlined),
              const SizedBox(height: 14),

              // ── Pays ────────────────────────────────
              _SectionLabel(label: 'VOTRE PAYS'),
              const SizedBox(height: 10),
              _CountryDropdown(
                selectedCountry: _selectedCountry,
                onChanged: (country) => setState(() {
                  _selectedCountry  = country;
                  _selectedReseller = null;
                }),
              ),
              const SizedBox(height: 14),

              // ── Revendeur ────────────────────────────
              if (_selectedCountry != null) ...[
                _SectionLabel(label: 'VOTRE REVENDEUR'),
                const SizedBox(height: 10),
                _ResellerDropdown(
                  country: _selectedCountry!,
                  selectedReseller: _selectedReseller,
                  onChanged: (reseller) => setState(() =>
                    _selectedReseller = reseller),
                ),
                const SizedBox(height: 14),
              ],

              _InfoBox(
                message : '⏳ Votre compte sera activé après validation de votre distributeur.',
                color   : Colors.blue),
              const SizedBox(height: 24),
            ],

            // ── Champs EMPLOYÉ ───────────────────────
            if (_selectedRole == AppRoles.employe) ...[
              _SectionLabel(label: 'VOTRE ENTREPRISE'),
              const SizedBox(height: 10),
              _InputField(
                controller : _entrepriseCtrl,
                label      : 'Nom de votre entreprise',
                icon       : Icons.domain_outlined),
              const SizedBox(height: 10),
              _InfoBox(
                message : '⏳ Votre compte sera activé après validation de votre entreprise.',
                color   : Colors.purple),
              const SizedBox(height: 24),
            ],

            // ── Erreur ───────────────────────────────
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Text(_error!,
                  style: const TextStyle(color: Colors.red,
                    fontSize: 12, fontWeight: FontWeight.w600))),
              const SizedBox(height: 14),
            ],

            // ── Bouton inscription ───────────────────
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor : Colors.white,
                  foregroundColor : Colors.black,
                  shape           : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
                child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                  : Text(_lang.t('registerBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 13, letterSpacing: 2)),
              ),
            ),
            const SizedBox(height: 24),

            // ── Lien connexion ───────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_lang.t('alreadyAccount'),
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Text(_lang.t('signIn'),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// ÉCRAN D'ATTENTE — affiché après inscription
// ─────────────────────────────────────────────────

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withOpacity(0.3), width: 2)),
                child: const Icon(Icons.hourglass_empty_rounded,
                  color: Color(0xFF22D3EE), size: 36)),
              const SizedBox(height: 28),
              const Text('Compte en attente',
                style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              Text(
                'Votre inscription a bien été enregistrée.\n\nVotre compte est en cours de validation. Vous recevrez un email de confirmation dès qu\'il sera activé.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 14,
                  height: 1.6)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (_) => false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor : Colors.white,
                    foregroundColor : Colors.black,
                    shape           : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                  child: const Text('Accéder à l\'app',
                    style: TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 13, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// WIDGETS RÉUTILISABLES
// ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label,
        style: TextStyle(color: Colors.grey[400], fontSize: 11,
          fontWeight: FontWeight.w900, letterSpacing: 3)));
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _RoleChip({required this.label, required this.icon,
    required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.white.withOpacity(0.08),
              width: selected ? 1.5 : 1)),
          child: Column(children: [
            Icon(icon, color: selected ? color : Colors.grey[600], size: 22),
            const SizedBox(height: 6),
            Text(label,
              style: TextStyle(
                color      : selected ? color : Colors.grey[600],
                fontSize   : 12,
                fontWeight : FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _DistributeurDropdown extends StatelessWidget {
  final List<dynamic> distributeurs;
  final String? selectedId;
  final Function(String id, String email) onChanged;
  const _DistributeurDropdown({
    required this.distributeurs,
    required this.selectedId,
    required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value       : selectedId,
          isExpanded  : true,
          dropdownColor: const Color(0xFF0D0D0D),
          hint        : Text('Sélectionnez votre distributeur',
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          icon        : Icon(Icons.expand_more, color: Colors.grey[600]),
          items       : distributeurs.map((doc) {
            final name  = doc.data['name']  as String? ?? 'Distributeur';
            final email = doc.data['email'] as String? ?? '';
            return DropdownMenuItem<String>(
              value: doc.$id,
              child: Row(children: [
                Icon(Icons.storefront_outlined,
                  color: const Color(0xFF1E88E5), size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                    style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
              ]),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final doc   = distributeurs.firstWhere((d) => d.$id == id);
            final email = doc.data['email'] as String? ?? '';
            onChanged(id, email);
          },
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String message;
  final Color color;
  const _InfoBox({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Text(message,
        style: TextStyle(color: color.withOpacity(0.9),
          fontSize: 12, fontWeight: FontWeight.w500, height: 1.5)));
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  const _InputField({required this.controller, required this.label,
    required this.icon, this.obscure = false, this.keyboardType, this.suffix});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller, obscureText: obscure, keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14,
        fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText  : label,
        labelStyle : TextStyle(color: Colors.grey[500], fontSize: 13),
        prefixIcon : Icon(icon, color: Colors.grey[600], size: 18),
        suffixIcon : suffix,
        filled     : true,
        fillColor  : const Color(0xFF0D0D0D),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}
// ─────────────────────────────────────────────────
// DONNÉES PAYS / REVENDEURS
// ─────────────────────────────────────────────────
const Map<String, List<String>> _resellersData = {
  'Australia':          ['APS', 'Nuflow Australia', 'Pipe Core'],
  'Austria':            ['Uground', 'König'],
  'Belgium':            ['Alpha Drain', 'Triviex'],
  'Bosnia Herzegovina': ['Mega Systems'],
  'Brunai':             ['IRR'],
  'Canada':             ['Formadrain', 'Nuflow'],
  'Chile':              ['Glemflow'],
  'China':              ['You Best'],
  'Colombia':           ['VE Group'],
  'Croatia':            ['No-Dig Croatia'],
  'Cyprus':             ['Green Moles'],
  'Czech Republic':     ['Ibos', 'Radeton'],
  'Denmark':            ['DKRT'],
  'Estonia':            ['Lateral Repairs', 'Re4M', 'Telger'],
  'EU':                 ['Vortex Europe'],
  'Finland':            ['Re4M', 'Pipemade', 'Sacpro'],
  'France':             ['Robocana', 'FDS', 'IRR'],
  'Germany':            ['Brawoliner', 'Fluvius', 'Polypipe', 'Schwalm Robotic'],
  'Global':             ['Brawoliner', 'Nuflow', 'APS'],
  'Greece':             ['Green Moles'],
  'Greenland':          ['IRR'],
  'Holland':            ['Sewer Supply'],
  'Hong Kong':          ['PD Tech'],
  'Hungary':            ['Robotechnic'],
  'Iceland':            ['IRR', 'Oliner'],
  'India':              ['Global Biz'],
  'Indonesia':          ['Perma-Liner Singapore'],
  'Ireland':            ['UTS', 'TCS', 'OC Mecanical'],
  'Israel':             ['Smart Line Robotics'],
  'Italy':              ['Nuova Contec', 'Vivax'],
  'Japan':              ['Kantool'],
  'Latvia':             ['Lateral Repairs', 'Re4M'],
  'Lithuania':          ['Lateral Repairs'],
  'Luxemburg':          ['Picote customers'],
  'Malaysia':           ['Tri Expert'],
  'Malta':              ['Picote customers'],
  'Mexico':             ['Generagua'],
  'Multi country':      ['Trelleborg'],
  'Namibia':            ['AMT', 'Nuflow South Africa'],
  'New Zealand':        ['APS', 'Nuflow Australia', 'Pipe Core'],
  'Norway':             ['Fluxus', 'Peantas', 'Relining Varuhuset'],
  'Oman':               ['Blue Hat', 'IRR'],
  'Poland':             ['Rafnar', 'Wodnick', 'WMG'],
  'Portugal':           ['Tescan'],
  'Romania':            ['GTSS Romania', 'Elpex'],
  'Saudi Arabia':       ['Blue Hat', 'IRR'],
  'Serbia':             ['Korekt'],
  'Singapore':          ['Syntech', 'Perma-Liner Singapore'],
  'Slovakia':           ['Ibos', 'Radeton'],
  'Slovania':           ['Sanikom'],
  'South Africa':       ['AMT', 'Nuflow South Africa'],
  'South Korea':        ['ESH Engineering'],
  'Spain':              ['Tescan', 'Panatec', 'JBP'],
  'Sweden':             ['Fluxus', 'Peantas', 'Relining Varuhuset'],
  'Switzerland':        ['Rimtec'],
  'Taiwan':             ['Tai Yuan'],
  'Thailand':           ['IRR'],
  'Turkey':             ['Guneri Markina'],
  'UAE':                ['Blue Hat', 'IRR'],
  'UK':                 ['CJ Kelly', 'RSM', 'Source1 UK', 'Spartan Tool UK'],
  'USA':                ['WRT', 'Hammerhead', 'Primeline', 'Jetter Depot',
                         'Tucson Winsupply', 'Maxliner', 'Source1 USA',
                         'Schwalm', 'Vortex', 'Nuflow', 'Spartan Tool',
                         'Roto-Rooter', 'Western Drain', 'Standard Plumbing',
                         'AJ Coleman'],
};

// ─────────────────────────────────────────────────
// DROPDOWN PAYS
// ─────────────────────────────────────────────────
class _CountryDropdown extends StatelessWidget {
  final String? selectedCountry;
  final ValueChanged<String?> onChanged;
  const _CountryDropdown({required this.selectedCountry, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final countries = _resellersData.keys.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCountry,
          isExpanded: true,
          dropdownColor: const Color(0xFF0A0A0F),
          hint: Row(children: [
            Icon(Icons.flag_outlined, color: Colors.grey[600], size: 18),
            const SizedBox(width: 10),
            Text('Sélectionner votre pays',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
          items: countries.map((c) => DropdownMenuItem(
            value: c,
            child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 13)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// DROPDOWN REVENDEUR
// ─────────────────────────────────────────────────
class _ResellerDropdown extends StatelessWidget {
  final String country;
  final String? selectedReseller;
  final ValueChanged<String?> onChanged;
  const _ResellerDropdown({
    required this.country,
    required this.selectedReseller,
    required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final resellers = _resellersData[country] ?? [];
    if (resellers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.25))),
        child: const Text('Aucun revendeur pour ce pays.\nContactez BzBots directement.',
          style: TextStyle(color: Colors.orange, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedReseller,
          isExpanded: true,
          dropdownColor: const Color(0xFF0A0A0F),
          hint: Row(children: [
            Icon(Icons.store_outlined, color: Colors.grey[600], size: 18),
            const SizedBox(width: 10),
            Text('Sélectionner votre revendeur',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
          items: resellers.map((r) => DropdownMenuItem(
            value: r,
            child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 13)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
