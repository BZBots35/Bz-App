import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/lang_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Masque la barre de navigation Android (garde la barre du haut : heure, batterie…)
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [SystemUiOverlay.top],
  );

  await LangService().init();
  runApp(const BZBotsApp());
}

class BZBotsApp extends StatefulWidget {
  const BZBotsApp({super.key});

  static void setLocale(BuildContext context) {
    _BZBotsAppState? state = context.findAncestorStateOfType<_BZBotsAppState>();
    state?.rebuild();
  }

  @override
  State<BZBotsApp> createState() => _BZBotsAppState();
}

class _BZBotsAppState extends State<BZBotsApp> with WidgetsBindingObserver {
  final _lang = LangService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lang.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // L'OS réaffiche parfois la barre de navigation au retour au premier plan
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [SystemUiOverlay.top],
      );
    }
  }

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _lang.textDirection,
      child: MaterialApp(
        title: 'BZBots Suite',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF050505),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF22D3EE),
            secondary: Color(0xFFA855F7),
            surface: Color(0xFF0A0A0F),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 800));

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity != ConnectivityResult.none;

    final auth = AuthService();

    if (!isOnline) {
      // ── Hors ligne au démarrage ──────────────
      final cached = await auth.getCachedSession();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => cached != null
              ? const HomeScreen()
              : const LoginScreen(),
          ),
        );
      }
      return;
    }

    // ── En ligne — comportement normal ─────────
    final user = await auth.getCurrentUser();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user != null ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 30)],
              ),
              child: const Center(
                child: Text('BZ',
                  style: TextStyle(color: Colors.black,
                    fontWeight: FontWeight.w900, fontSize: 24)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('BZBots',
              style: TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text('Suite Enterprise AI',
              style: TextStyle(color: Colors.grey[600], fontSize: 12, letterSpacing: 3)),
            const SizedBox(height: 40),
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
