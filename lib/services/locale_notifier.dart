import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';

/// Holds the chosen UI language and persists it across launches
/// (SharedPreferences). Defaults to Traditional Chinese; the Settings page lets
/// the user switch to English.
class LocaleNotifier with ChangeNotifier {
  LocaleNotifier() {
    _load();
  }

  static const _prefKey = 'ui_locale';

  AppLocale _locale = AppLocale.zhHant;
  AppLocale get locale => _locale;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefKey);
      if (v != null) {
        _locale = AppLocaleX.fromPref(v);
        notifyListeners();
      }
    } catch (_) {
      // No persistence available (e.g. tests) — keep the default.
    }
  }

  Future<void> setLocale(AppLocale next) async {
    if (_locale == next) return;
    _locale = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, next.prefValue);
    } catch (_) {
      // Best-effort persistence.
    }
  }
}
