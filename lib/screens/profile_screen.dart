// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/app_roles.dart';
import '../services/lang_service.dart';
import 'login_screen.dart';
import 'entreprise_panel_screen.dart';
import 'distributeur_panel_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth        = AuthService();
  final _lang        = LangService();
  final _nameCtr     = TextEditingController();
  final _passCtr     = TextEditingController();
  final _confirmCtr  = TextEditingController();

  String       _email      = '';
  String       _role       = AppRoles.entreprise;
  String       _status     = AppRoles.statusActive;
  String       _userId     = '';
  String       _reseller   = '';
  List<String> _products   = [];
  String?      _photoPath;
  bool         _loadingName = false;
  bool         _loadingPass = false;
  bool         _showPass    = false;
  bool         _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user  = await _auth.getCurrentUser();
    final prefs = await SharedPreferences.getInstance();
    if (user != null && mounted) {
      final role     = await _auth.getUserRole(user.$id);
      final status   = await _auth.getUserStatus(user.$id);
      final products = await _auth.getUserProducts(user.$id);
      final reseller = await _auth.getUserReseller(user.$id);
      setState(() {
        _nameCtr.text = user.name;
        _email        = user.email;
        _userId       = user.$id;
        _role         = role;
        _status       = status;
        _products     = products;
        _reseller     = reseller;
        _photoPath    = prefs.getString('photo_path');
      });
    }
  }

  Future<void> _saveName() async {
    if (_nameCtr.text.trim().isEmpty) return;
    setState(() => _loadingName = true);
    try {
      await _auth.updateName(_nameCtr.text.trim());
      if (mounted) _showSnack(
        _lang.t('nameSaved'), const Color(0xFF22D3EE));
    } catch (e) {
      if (mounted) _showSnack('${_lang.t('errorPrefix')} $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingName = false);
    }
  }

  Future<void> _savePassword() async {
    if (_passCtr.text.length < 8) {
      _showSnack(_lang.t('passwordMin8'), Colors.orange); return;
    }
    if (_passCtr.text != _confirmCtr.text) {
      _showSnack(_lang.t('passwordMismatch'), Colors.orange); return;
    }
    setState(() => _loadingPass = true);
    try {
      await _auth.updatePassword(_passCtr.text.trim());
      _passCtr.clear(); _confirmCtr.clear();
      if (mounted) _showSnack(
        _lang.t('passwordSaved'), const Color(0xFF22D3EE));
    } catch (e) {
      if (mounted) _showSnack('${_lang.t('errorPrefix')} $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingPass = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('photo_path', picked.path);
      setState(() => _photoPath = picked.path);
      _showSnack(_lang.t('nameSaved'), const Color(0xFF22D3EE));
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(_lang.t('profilePhoto'),
            style: TextStyle(color: Colors.grey[400],
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 16),
          _sheetBtn(Icons.photo_library_outlined, _lang.t('photoGallery'),
            () => _pickPhoto(ImageSource.gallery)),
          const SizedBox(height: 10),
          _sheetBtn(Icons.camera_alt_outlined, _lang.t('photoCamera'),
            () => _pickPhoto(ImageSource.camera)),
          if (_photoPath != null) ...[
            const SizedBox(height: 10),
            _sheetBtn(Icons.delete_outline, _lang.t('photoDelete'), () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('photo_path');
              setState(() => _photoPath = null);
            }, color: Colors.red),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _sheetBtn(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.15))),
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: c,
            fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showLangPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('LANGUE / LANGUAGE', style: TextStyle(
              color: Colors.grey[400], fontSize: 11,
              fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 2.5,
                crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: LangService.languages.length,
              itemBuilder: (_, i) {
                final code     = LangService.languages.keys.elementAt(i);
                final label    = LangService.languages[code]!;
                final selected = code == _lang.currentLang;
                return GestureDetector(
                  onTap: () {
                    _lang.setLang(code);
                    setState(() {});
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                        ? const Color(0xFF22D3EE).withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                          ? const Color(0xFF22D3EE).withOpacity(0.5)
                          : Colors.white.withOpacity(0.08))),
                    child: Center(
                      child: Text(label,
                        style: TextStyle(
                          color: selected
                            ? const Color(0xFF22D3EE)
                            : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Text(_lang.t('logoutTitle'),
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(_lang.t('logoutConfirm'),
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_lang.t('logoutCancel'),
              style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white),
            child: Text(_lang.t('logoutConfirmBtn'),
              style: const TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _auth.logout();
      Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = Color(AppRoles.roleColor(_role));
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Text(_lang.t('profile').toUpperCase(),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // ── Avatar ────────────────────────────────
          Center(
            child: Stack(children: [
              GestureDetector(
                onTap: _showPhotoOptions,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: roleColor.withOpacity(0.4), width: 2),
                    boxShadow: [BoxShadow(
                      color: roleColor.withOpacity(0.15),
                      blurRadius: 20)]),
                  child: ClipOval(
                    child: _photoPath != null && File(_photoPath!).existsSync()
                      ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFF0D0D0D),
                          child: Center(child: Text(
                            _nameCtr.text.isNotEmpty
                              ? _nameCtr.text[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w900, fontSize: 36)))),
                  ),
                ),
              ),
              Positioned(bottom: 0, right: 0,
                child: GestureDetector(
                  onTap: _showPhotoOptions,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2)),
                    child: const Icon(Icons.camera_alt,
                      color: Colors.black, size: 14)),
                )),
            ]),
          ),
          const SizedBox(height: 10),
          Text(_email,
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 6),

          // ── Badges rôle + statut ──────────────────
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: roleColor.withOpacity(0.4))),
              child: Text(AppRoles.label(_role),
                style: TextStyle(color: roleColor, fontSize: 9,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _statusColor.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_statusIcon, color: _statusColor, size: 10),
                const SizedBox(width: 4),
                Text(_statusLabel,
                  style: TextStyle(color: _statusColor, fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 1)),
              ])),
          ]),
          if (_reseller.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.storefront_outlined, color: Colors.grey[600], size: 13),
              const SizedBox(width: 5),
              Text('${_lang.t('resellerLabel')} $_reseller',
                style: TextStyle(color: Colors.grey[500], fontSize: 12,
                  fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 32),

          // ── Modifier le nom ───────────────────────
          _sectionTitle(_lang.t('nameAndFirstname'), Icons.person_outline),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.07))),
            child: Column(children: [
              TextField(
                controller: _nameCtr,
                style: const TextStyle(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: _lang.t('fullName'),
                  labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                  prefixIcon: Icon(Icons.person_outline,
                    color: Colors.grey[600], size: 18),
                  filled: true, fillColor: Colors.black.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.08))),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.08))),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF22D3EE), width: 1.5))),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton(
                  onPressed: _loadingName ? null : _saveName,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22D3EE),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                  child: _loadingName
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                    : Text(_lang.t('saveBtn'),
                        style: const TextStyle(fontWeight: FontWeight.w900,
                          fontSize: 12, letterSpacing: 1.5)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Changer le mot de passe ───────────────
          _sectionTitle(_lang.t('passwordSection'), Icons.lock_outline),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.07))),
            child: Column(children: [
              _passField(_passCtr, _lang.t('newPassword'),
                _showPass, () => setState(() => _showPass = !_showPass)),
              const SizedBox(height: 12),
              _passField(_confirmCtr, _lang.t('confirmPassword'),
                _showConfirm,
                () => setState(() => _showConfirm = !_showConfirm)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton(
                  onPressed: _loadingPass ? null : _savePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAB308),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                  child: _loadingPass
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                    : Text(_lang.t('changePasswordBtn'),
                        style: const TextStyle(fontWeight: FontWeight.w900,
                          fontSize: 12, letterSpacing: 1.5)),
                ),
              ),
            ]),
          ),

          // ── Panel Entreprise ──────────────────────
          if (AppRoles.isEntreprise(_role)) ...[
            const SizedBox(height: 24),
            _sectionTitle(
              _lang.t('myEmployeesSection'), Icons.badge_outlined),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => EntreprisePanelScreen(
                  entrepriseId       : _userId,
                  entrepriseName     : _nameCtr.text,
                  entrepriseProducts : _products))),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF8E24AA).withOpacity(0.3))),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E24AA).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.badge_outlined,
                      color: Color(0xFF8E24AA), size: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_lang.t('manageEmployees'),
                        style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(_lang.t('manageEmployeesDesc'),
                        style: TextStyle(
                          color: Colors.grey[600], fontSize: 11)),
                    ])),
                  Icon(Icons.chevron_right,
                    color: const Color(0xFF8E24AA).withOpacity(0.6),
                    size: 20),
                ]),
              ),
            ),
          ],

          // ── Panel Distributeur ────────────────────
          if (AppRoles.isDistributeur(_role)) ...[
            const SizedBox(height: 24),
            _sectionTitle(
              _lang.t('myCompaniesSection'), Icons.storefront_outlined),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DistributeurPanelScreen(
                  distributeurId   : _userId,
                  distributeurName : _nameCtr.text))),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF1E88E5).withOpacity(0.3))),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E88E5).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.storefront_outlined,
                      color: Color(0xFF1E88E5), size: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_lang.t('manageCompanies'),
                        style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(_lang.t('manageCompaniesDesc'),
                        style: TextStyle(
                          color: Colors.grey[600], fontSize: 11)),
                    ])),
                  Icon(Icons.chevron_right,
                    color: const Color(0xFF1E88E5).withOpacity(0.6),
                    size: 20),
                ]),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Langue ───────────────────────────────
          _sectionTitle(_lang.t('language'), Icons.language_outlined),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showLangPicker(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFEAB308).withOpacity(0.3))),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAB308).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.language_outlined,
                    color: Color(0xFFEAB308), size: 22)),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_lang.t('language'),
                      style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(LangService.languages[_lang.currentLang] ?? '',
                      style: TextStyle(
                        color: Colors.grey[500], fontSize: 12)),
                  ])),
                Icon(Icons.chevron_right,
                  color: const Color(0xFFEAB308).withOpacity(0.6), size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          // ── Déconnexion ───────────────────────────
          _sectionTitle(_lang.t('sessionSection'), Icons.power_settings_new),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(_lang.t('logoutBtn'),
                style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 12, letterSpacing: 1.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.12),
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
                elevation: 0),
            ),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  // ── Helpers statut ───────────────────────────────
  Color get _statusColor {
    switch (_status) {
      case AppRoles.statusActive:    return const Color(0xFF43A047);
      case AppRoles.statusSuspended: return Colors.red;
      default:                       return Colors.orange;
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case AppRoles.statusActive:    return Icons.check_circle_outline;
      case AppRoles.statusSuspended: return Icons.block_outlined;
      default:                       return Icons.hourglass_empty_rounded;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case AppRoles.statusActive:    return _lang.t('statusActiveDisplay');
      case AppRoles.statusSuspended: return _lang.t('statusSuspendedDisplay');
      default:                       return _lang.t('statusPendingDisplay');
    }
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(children: [
        Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.1),
            borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: const Color(0xFF22D3EE), size: 15)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
      ]),
    );
  }

  Widget _passField(TextEditingController ctrl, String label,
      bool show, VoidCallback toggle) {
    return TextField(
      controller: ctrl,
      obscureText: !show,
      style: const TextStyle(color: Colors.white, fontSize: 14,
        fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
        prefixIcon: Icon(Icons.lock_outline,
          color: Colors.grey[600], size: 18),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[600], size: 18),
          onPressed: toggle),
        filled: true, fillColor: Colors.black.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFEAB308), width: 1.5))),
    );
  }
}