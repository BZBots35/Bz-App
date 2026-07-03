// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/auth_service.dart';
import '../services/lang_service.dart';
import 'register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _auth         = AuthService();
  final _lang         = LangService();
  bool _loading  = false;
  bool _showPass = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });

    final online = await _isOnline();

    // ── Mode hors ligne ────────────────────────
    if (!online) {
      final cached = await _auth.getCachedSession();
      if (cached != null &&
          cached['email']?.toLowerCase() == _emailCtrl.text.trim().toLowerCase()) {
        // On a une session valide pour cet email — on entre sans vérifier le mdp
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final done  = prefs.getBool('onboarding_done') ?? false;
          Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => done
              ? const HomeScreen()
              : const OnboardingScreen()),
            (_) => false);
        }
      } else {
        setState(() => _error = _lang.t('offlineNoSession'));
      }
      setState(() => _loading = false);
      return;
    }

    // ── Mode en ligne — comportement normal ────
    try {
      await _auth.login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final done  = prefs.getBool('onboarding_done') ?? false;
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => done
            ? const HomeScreen()
            : const OnboardingScreen()),
          (_) => false);
      }
    } catch (e) {
      setState(() => _error = _lang.t('invalidCredentialsFr'));
    } finally {
      setState(() => _loading = false);
    }
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
            Text('LANGUE / LANGUAGE',
              style: TextStyle(color: Colors.grey[400], fontSize: 11,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _showLangPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1))),
                  child: Text(
                    LangService.languages[_lang.currentLang] ?? '🇫🇷 FR',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(height: 36),

            Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.white.withOpacity(0.2),
                    blurRadius: 24)]),
                child: const Center(child: Text('BZ',
                  style: TextStyle(color: Colors.black,
                    fontWeight: FontWeight.w900, fontSize: 22)))),
              const SizedBox(height: 16),
              const Text('BZBots',
                style: TextStyle(color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(_lang.t('enterpriseAISuite'),
                style: TextStyle(color: Colors.grey[500], fontSize: 12,
                  letterSpacing: 3, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 44),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(_lang.t('login').toUpperCase(),
                style: TextStyle(color: Colors.grey[400], fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 3))),
            const SizedBox(height: 20),

            _InputField(
              controller  : _emailCtrl,
              label       : _lang.t('email'),
              icon        : Icons.email_outlined,
              keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _InputField(
              controller : _passwordCtrl,
              label      : _lang.t('password'),
              icon       : Icons.lock_outline,
              obscure    : !_showPass,
              suffix     : IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600], size: 18),
                onPressed: () => setState(() => _showPass = !_showPass))),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Text(_error!,
                  style: const TextStyle(color: Colors.red,
                    fontSize: 12, fontWeight: FontWeight.w600))),
            ],
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
                child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                  : Text(_lang.t('loginBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 13, letterSpacing: 2)),
              ),
            ),
            const SizedBox(height: 24),

            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_lang.t('noAccount'),
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              TextButton(
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(
                    builder: (_) => const RegisterScreen())),
                child: Text(_lang.t('createAccount'),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
            const SizedBox(height: 20),

            Text(_lang.t('legal'),
              style: TextStyle(color: Colors.grey[800],
                fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller   : controller,
      obscureText  : obscure,
      keyboardType : keyboardType,
      style        : const TextStyle(color: Colors.white,
        fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText  : label,
        labelStyle : TextStyle(color: Colors.grey[500], fontSize: 13),
        prefixIcon : Icon(icon, color: Colors.grey[600], size: 18),
        suffixIcon : suffix,
        filled     : true,
        fillColor  : const Color(0xFF0D0D0D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE), width: 1.5))),
    );
  }
}