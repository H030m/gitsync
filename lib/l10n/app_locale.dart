import 'package:flutter/widgets.dart';

/// The two UI languages GitSync supports.
enum AppLocale { en, zhHant }

extension AppLocaleX on AppLocale {
  Locale get locale => switch (this) {
        AppLocale.en => const Locale('en'),
        AppLocale.zhHant => const Locale('zh', 'TW'),
      };

  /// Human label shown in the language switcher.
  String get label => switch (this) {
        AppLocale.en => 'English',
        AppLocale.zhHant => '中文（繁體）',
      };

  /// Stable key for persistence.
  String get prefValue => name;

  static AppLocale fromPref(String? v) => switch (v) {
        'en' => AppLocale.en,
        'zhHant' => AppLocale.zhHant,
        _ => AppLocale.zhHant, // default: Traditional Chinese
      };
}
