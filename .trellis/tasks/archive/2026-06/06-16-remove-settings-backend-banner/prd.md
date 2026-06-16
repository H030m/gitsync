# 移除 Settings 頂端 Backend:LIVE 區塊

## Goal
拿掉 Settings 頁最上面的「Backend: LIVE/FAKE」資訊 banner(`_BackendBanner`)。純 UI 移除。

## Requirements
* 移除 `lib/views/settings/settings_page.dart` 第一個 `StaggeredEntry`(key `settings-banner`,包 `const _BackendBanner()`)。
* 刪除 `_BackendBanner` widget class(~406+)及其專用 helper。
* 清掉因此不再使用的 import(如 `AppConfig`,若 settings 內已無其他用途)與 l10n 字串(grep 確認 unused 才刪)。
* 其餘 Settings 內容不動;亮/暗色不受影響。

## Acceptance Criteria
* [ ] Settings 頂端不再有 Backend banner。
* [ ] 無 dangling 參考 / 未用 import / 未用字串殘留。
* [ ] flutter analyze + test 綠(調整受影響的 settings widget 測試,若有)。

## Out of Scope
* AppConfig 後端切換邏輯本身(只是不再於 Settings 顯示)。
* 其他 Settings 項目。
