import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations/index.dart';

class LangService extends ChangeNotifier {
  static final LangService _instance = LangService._internal();
  factory LangService() => _instance;
  LangService._internal();

  String _currentLang = 'fr';
  String get currentLang => _currentLang;

  static const Map<String, String> languages = {
    'fr': '🇫🇷 FR',
    'en': '🇬🇧 EN',
    'es': '🇪🇸 ES',
    'de': '🇩🇪 DE',
    'it': '🇮🇹 IT',
    'pt': '🇵🇹 PT',
    'ar': '🇸🇦 AR',
    'zh': '🇨🇳 ZH',
    'ja': '🇯🇵 JA',
    'ko': '🇰🇷 KO',
    'ru': '🇷🇺 RU',
    'da': '🇩🇰 DA',
    'hi': '🇮🇳 HI',
  };

  // Charge la langue sauvegardée
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLang = prefs.getString('lang') ?? 'fr';
    notifyListeners();
  }

  // Change la langue et la sauvegarde
  Future<void> setLang(String lang) async {
    if (!languages.containsKey(lang)) return;
    _currentLang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
    notifyListeners();
  }

  // Traduit une clé
  String t(String key) {
    return Translations.all[_currentLang]?[key]
        ?? Translations.all['fr']?[key]
        ?? key;
  }

  // Sens d'écriture (pour l'arabe)
  TextDirection get textDirection =>
      _currentLang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}
