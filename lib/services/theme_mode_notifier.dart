import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ChangeNotifier for theme switching. Persists the choice across launches and
// web refresh (F5) via SharedPreferences, mirroring LocaleNotifier — without it
// every fresh page load resets to the ThemeMode.system default.
class ThemeModeNotifier with ChangeNotifier {
  ThemeModeNotifier() {
    _load();
  }

  static const _prefKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final parsed = _parse(prefs.getString(_prefKey));
      if (parsed != null && parsed != _mode) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (_) {
      // No persistence available (e.g. tests) — keep the default.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _mode.name);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static ThemeMode? _parse(String? v) {
    switch (v) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}
