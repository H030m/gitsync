# 每日彙整:移除日報 count chip 與 Discord digest 鎖圖標

## Goal

精簡 Daily 頁:移除 (1) 日報卡右上角的 commit 數 / 訊息數 chip + 圖標,(2) Discord 摘要右上角的「鎖」圖標(lock toggle)。純 UI 移除。手機 App;亮/暗色都要正常(專案規則)。

## Requirements

* 移除 `_DayReportCard` header 的 `_CountChip`(commitCount + messageCount,`daily_view_page.dart:522-535`);若 `_CountChip` 類別變成完全沒人用,一併刪除(grep 確認)。
* 移除 `_DayDigestSection` 右上角的鎖 toggle(`digest.locked` / `isTogglingLock`,~714-718)的 **UI 控制項**。
* **保留後端**:`setDigestLock` callable、`DiscordDigest.locked` 欄位、VM 的 lock 邏輯都不刪(只移除這個 UI 入口);commitCount/messageCount model 欄位不刪。

## Acceptance Criteria

* [ ] 日報卡右上角不再有 commit/訊息數 chip 與圖標。
* [ ] Discord 摘要區不再有鎖圖標/按鈕。
* [ ] 移除後無 dangling 參考、無未用 import/widget/字串殘留(grep 確認後清掉)。
* [ ] 亮/暗色正常;flutter analyze + 既有 flutter test 綠燈(調整受影響的 widget 測試)。

## 追加範圍（user 後續要求：整個移除 locked + AI 調整）

完整移除兩個功能,跨 functions / Flutter app / discord-bot 三處:

**A. `locked`(digest 凍結)**
* functions:`handlers/setDigestLock.ts`(刪 + index.ts unexport);`flows/discordDailyDigest.ts` / `discordRangeDigest.ts` 的「locked 就跳過重生」防護(移除 → 永遠重生);相關測試。
* Flutter:`models/discord_digest.dart` 的 `locked` 欄位;`view_models/discord_messages_vm.dart` 的 `toggleLock`/`isTogglingLock`/`_togglingDates`;`services/functions_service.dart` 的 `setDigestLock`(抽象+impl)+ `fake_functions_service.dart` + `fake_discord_digest_repo.dart` 的 locked/frozen 邏輯。

**B. AI 調整(editDiscordDigest)**
* functions:`handlers/editDiscordDigest.ts`、`handlers/botEditDigest.ts`、`flows/editDiscordDigest.ts`、`prompts/editDiscordDigest.ts`(刪 + index.ts unexport);`tools/agentTrace.ts` 的 `'editDiscordDigest'` label;相關測試。
* Flutter:`daily_view_page.dart` `_DayDigestSection` 的 AI-adjust 輸入框 + `_adjustController`/`_submitAdjust`;`functions_service.dart` 的 `editDiscordDigest` + fakes + VM 對應方法。
* **discord-bot**:`commands.ts` 的 `/gitsync-digest` 編輯指令、`config.ts` 的 `editDigestUrl`(否則 bot 打到已刪 endpoint 會壞)。

**行為後果(已與 user 確認接受)**:Discord 摘要不再能被凍結或 AI 調整;每天重新 fetch 都會重新生成。

## Acceptance Criteria（追加）

* [ ] 全 repo grep 不到 `setDigestLock` / `editDiscordDigest` / `botEditDigest` / `toggleLock` / digest `locked` 的殘留參考。
* [ ] functions build + lint + test 綠;flutter analyze + test 綠;discord-bot(若有 build/lint)綠。
* [ ] discordDailyDigest 不再有 locked 分支(永遠重生)。

## Out of Scope

* 刪後端 lock 邏輯 / setDigestLock callable / model 欄位。
* 其他 Daily 頁版面改動。

## Technical Notes

* 主檔:`lib/views/daily/daily_view_page.dart`(+ 可能 `app_strings.dart` 未用字串)。
* 受影響測試:grep `_CountChip` / `lock` / 相關 test。
* 注意:這與先前「統計那邊不要碰」相反——user 現在明確要移除這些 count chip。
