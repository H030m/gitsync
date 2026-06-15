# 每日彙整:合併 Discord 與摘要 + 精簡子標題

## Goal

把「每日彙整 (Daily)」頁目前分開的 **摘要分頁(日報)** 與 **Discord 分頁(Discord 摘要)** 合併呈現,並精簡過多的子標題,降低閱讀負擔。手機 App;UI 需同時做亮色與暗色(專案規則)。

## 現況(已從程式碼確認)

* `lib/views/daily/daily_view_page.dart` 有兩個分頁:
  * **Summary 分頁**:`_ReportsPanel` → 日報卡 `_DayReportBody`,含 `摘要`敘述 + 三張寫死的卡:`_HighlightsCard`(重點)/`_CommitRollupCard`(提交彙總)/`_ContributionsCard`(貢獻);下方 `Ask GitSync` 聊天(AskRepoViewModel,整 repo)。
  * **Discord 分頁**:`_DigestPanel` → `_DigestCard` 直接 render `MarkdownView(digest.markdown)`(AI 生成、含 AI 自加的粗體子標題)+ 來源訊息;下方 `問 Discord` 聊天(DiscordChatViewModel,限 Discord)。
* 資料源:日報 `dailyReports/{date}`(`summarizeDay`);Discord `discordDigests/{date}`(`discordDailyDigest`)——**兩個獨立 Firestore doc + 兩個獨立 flow**。
* 子標題來源:**日報卡片標題寫死在 Flutter**(`app_strings`:highlights/commitRollup/contributions);**Discord 子標題是 AI markdown**(prompt `discordDailyDigest.ts` 叫它「用粗體 header 分組」)。

## Decisions（已與 user 確認）

* **D1 = UI 合併成一頁**:拿掉 Summary / Discord 兩個分頁,合成單一每日視圖;每天同時顯示「日報 + Discord 摘要」。**資料源與後端 flow 不變**(仍兩個 Firestore doc)。
* **D2 = 只留一個整合聊天**:保留 `Ask GitSync`(askRepo,能搜 commit+Discord+task),**移除限 Discord 的聊天 UI**(`_DiscordChat`)。後端 `discordChat` flow 不刪(僅 UI 不再用),屬 out of scope。
* **D3 = 留「摘要」+「貢獻」,其餘合併**:日報把 `重點(Highlights)` + `blockers` + `提交彙總(Commit rollup)` 收成**一塊**(例:活動重點 / Key activity);保留 `摘要`敘述 與 `貢獻`。Discord digest 改成**少用/不用粗體子標題**(prompt 調整,偏平鋪 bullet)。

## Technical Approach

1. **UI 合併**(`lib/views/daily/daily_view_page.dart`):
   - 移除 Summary/Discord 分頁切換,改為單一每日視圖;每天一張(沿用現有可收合卡片模式)同時呈現:`摘要`敘述 → 合併後的「活動重點」卡 → `貢獻`卡 → Discord 摘要 markdown(+來源訊息可展開)。
   - 該日視圖同時取 `DailyReportViewModel`(報告)與 `DiscordMessagesViewModel`(digest);用日期對齊兩者。
   - 下方只保留一個 `Ask GitSync` 聊天;移除 `_DiscordChat` 區塊與其專屬輸入。
2. **子標題精簡**:
   - 合併 `_HighlightsCard` + blockers + `_CommitRollupCard` 成單一卡(新標題字串,亮/暗色都做);保留 `_ContributionsCard` 與 `摘要`。
   - 清理 `app_strings.dart` 不再使用的標題字串(或新增合併後標題)。
3. **Discord 子標題**:`functions/src/prompts/discordDailyDigest.ts` 把「用粗體 header 分組」改成「優先平鋪 bullet、少用或不用子標題」。
4. **亮/暗色**:所有新增/調整的卡片、分隔、文字色都需在亮色與暗色模式下檢查(專案規則)。

## Refinements（user 看過第一版後的調整）

* **D7 移除參考訊息**:拿掉 Discord digest 的「參考訊息 / referenced messages」(`_DigestSourceMessages`)。
* **D8 活動重點再精簡**:只留 highlights(+blockers),**拿掉「提交彙總 / commit rollup」**那段。日報最終:摘要 + 重點(含 blockers)+ 貢獻。
* **D9 全頁 AI 內容強制中文**:Daily 頁全部 AI 產出中文 —— 日報摘要(summarizeDay)、Discord 摘要(discordDailyDigest)、Ask GitSync 聊天(askRepo)。沿用 W6 `language` plumbing 從 app locale 帶語言名;trigger 生成拿不到 locale 的(digest)在 prompt 明確要求中文。

* **D10 移除日報的「貢獻」卡**:刪掉 `_ContributionsCard`(每位成員 tasks/commits 的貢獻區塊)。日報最終只剩:摘要 + 重點(含 blockers)。**不可碰**:獨立的 Stats 頁(`lib/views/stats/stats_view_page.dart`,統計)、日報卡頂端的數量 chip(`_CountChip`)。DailyReport model 的 `memberContributions` 欄位不刪(只是不在此頁 render)。

## Acceptance Criteria

* [ ] Daily 頁不再有 Summary/Discord 兩個分頁;單一視圖每天同時看到日報 + Discord 摘要。
* [ ] 日報子卡從 4 塊降為:`摘要`(敘述)+「活動重點」(原 重點+blockers+提交彙總)+`貢獻`,共 3 區。
* [ ] 下方只有一個整合聊天(Ask GitSync);限 Discord 的聊天 UI 已移除。
* [ ] Discord 摘要的子標題明顯變少(prompt 調整後,新生成的 digest 偏平鋪)。
* [ ] 亮色與暗色模式都正確(對比、分隔、卡片背景)。
* [ ] 無資料/後端 flow 變更(除 Discord prompt);既有測試不退步;新增/調整的 widget 測試(若有)綠燈。

## Out of Scope

* 網頁版優化(手機為主)。
* 後端合成單一 flow/doc;刪除 `discordChat` 後端 flow。
* 改 summarizeDay / discordDailyDigest 的內容品質(只動結構/標題)。

## Out of Scope（暫定）

* 網頁版優化(專案規則:手機為主)。
* 改 summarizeDay / discordDailyDigest 的「內容品質」(只動結構/標題,不動產生邏輯)——除非 Q1 選後端合併。

## Technical Notes

* 主要檔:`lib/views/daily/daily_view_page.dart`(分頁/卡片重構)、`lib/l10n/app_strings.dart`(標題字串)。
* 若精簡 Discord 子標題:`functions/src/prompts/discordDailyDigest.ts`。
* 若合資料/欄位:`functions/src/flows/summarizeDay.ts` + `prompts/summarizeDay.ts` + `lib/models/daily_report.dart`(複雜度高)。
* UI 規則:亮/暗色都要做。
