# Daily 頁:範圍全空的空狀態 + 空白天收合成一行

## Goal

改善 Daily 頁在「沒資料」時的體驗(UX 審查 follow-up):
1. **範圍全空空狀態**:選的日期範圍內每天都沒活動時,顯示單一明確空狀態(圖示 + 說明 +「調整日期範圍」入口),而不是一排空卡。
2. **空白天收合成一行**:範圍內個別「沒活動」的天,收成一行精簡列(日期 + 無活動),不要每天都一張帶「產生報告」的空卡。

手機 App;亮/暗色都要做(專案規則)。

## 定義

* **某天「有活動」** = 該天有日報(`report.reportForDay(dayKey) != null`)**或** 有 Discord digest(`discord.digestForDate(dayKey) != null`)。
* **某天「空白」** = 兩者皆無。
* **範圍全空** = 範圍內所有天都空白。

## Requirements

* `_dayCards`(`lib/views/daily/daily_view_page.dart`)在組清單時:
  * 若範圍內**全部空白** → 不渲染逐日卡,改渲染**單一空狀態 widget**:icon + 文案(例:「這段期間沒有活動」)+ 一個「調整日期範圍」按鈕(觸發現有的日期範圍 picker)。
  * 否則:有活動的天照現有 `_DayReportCard` 顯示;**空白的天**改渲染**精簡一行**(日期 + 「無活動」灰字),不展開、不顯示產生報告空卡。
* 空白天的一行列仍可點擊**展開**以露出「產生報告」動作(保留產生入口,只是預設不佔版面)。
* 不動後端 / 資料 / VM 邏輯(只動 UI 呈現);沿用現有 `report.rangeDays`、`reportForDay`、`digestForDate`、日期 picker 觸發。

## Acceptance Criteria

* [ ] 範圍內全空 → 顯示單一空狀態(含「調整日期範圍」可開 picker),不再有一排空卡。
* [ ] 範圍內部分空白 → 空白天是精簡一行(日期 + 無活動),有活動的天正常卡片。
* [ ] 空白天一行可點開露出「產生報告」入口(產生功能不遺失)。
* [ ] 亮/暗色皆正確(colorScheme token,無硬編色);flutter analyze + test 綠;補對應 widget 測試。

## Out of Scope

* 改預設日期範圍的「天數」(本 task 只處理空狀態呈現;預設範圍值另議)。
* 日期標籤可讀性(相對日/週幾)——另一項 UX 建議,不在此 task。
* 後端 / VM 邏輯變更。

## Technical Notes

* 主檔:`lib/views/daily/daily_view_page.dart`(`_dayCards`、`_DayReportCard`、`_DayReportEmpty`)、`lib/l10n/app_strings.dart`(新空狀態/無活動字串,EN+ZH)。
* 日期 picker 觸發點:`_onRangeChanged` / AppBar 的 range picker(`vm.setRange`)——空狀態的「調整日期範圍」按鈕沿用同一入口。
* 判斷活動用 `report.reportForDay(dayKey)` + `discord.digestForDate(dayKey)`(兩個 VM 已在 `_dayCards` 取得)。
