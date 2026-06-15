# persist theme mode across refresh

## 問題

Flutter web 版按 F5（重整）後，主題會回到預設深色，使用者選的亮/暗設定遺失。
根因：`lib/services/theme_mode_notifier.dart` 的 `ThemeModeNotifier` 完全沒有持久化——
只存記憶體，預設 `ThemeMode.system`（深色 OS/瀏覽器下呈深色）。`setMode`/`toggle` 只
`notifyListeners()`、不寫儲存；建構子也不讀回。F5 → provider tree 重建 → 新實例回 system。

## 目標

主題選擇（system/light/dark）寫入 SharedPreferences、啟動時讀回，撐過 F5。預設維持
`ThemeMode.system`（只補持久化，不改預設）。

## 方案

照同層 `lib/services/locale_notifier.dart`（語言已正確持久化）的模式改
`theme_mode_notifier.dart`，公開 API（`mode`/`setMode`/`toggle`）與無參數建構子簽名不變：
- 建構子 fire-and-forget `_load()`：從 `SharedPreferences` 讀 `theme_mode` 字串 →
  解析回 `ThemeMode` → notify；catch 保持預設（測試無 prefs 不爆）。
- `setMode`/`toggle`：notify 後 best-effort `prefs.setString('theme_mode', _mode.name)`。
- `shared_preferences: ^2.3.2` 已是既有相依，免新增套件。

## 範圍外

- 不改預設值；不鏡射到 Firestore（主題純前端）；不動 provider tree / MaterialApp / 設定頁 UI。

## 驗收

- 新增 `test/theme_mode_notifier_test.dart`（用 `SharedPreferences.setMockInitialValues`）：
  讀回 light、寫入 dark、無值預設 system。
- `flutter analyze` 改動檔 0/0；`flutter test` 全綠。
- Web 手測（亮/暗）：切亮色 → F5 → 仍亮色。

## 動到的檔案

- `lib/services/theme_mode_notifier.dart`
- `test/theme_mode_notifier_test.dart`（new）
