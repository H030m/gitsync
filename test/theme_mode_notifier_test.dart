import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gitsync/services/theme_mode_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to system when nothing is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ThemeModeNotifier();
    // _load is async and fire-and-forget; let it settle.
    await Future<void>.delayed(Duration.zero);
    expect(notifier.mode, ThemeMode.system);
  });

  test('reads the persisted theme mode back on construction', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final notifier = ThemeModeNotifier();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.mode, ThemeMode.light);
  });

  test('setMode persists the choice (survives a fresh notifier)', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ThemeModeNotifier();
    await notifier.setMode(ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');

    // A new notifier (e.g. after F5) seeds from the stored value.
    final reloaded = ThemeModeNotifier();
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.mode, ThemeMode.dark);
  });

  test('toggle flips and persists', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final notifier = ThemeModeNotifier();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.mode, ThemeMode.dark);

    await notifier.toggle();
    expect(notifier.mode, ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });
}
