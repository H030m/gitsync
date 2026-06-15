# deep-link foreground notification taps to the task

## Goal

讓使用者點「前景時收到的推播通知」能直接導到對應任務詳情頁，而不是掉到空殼的
`NotifyScreen`（「從推播通知開啟」佔位頁）。完成原始 TODO：解析通知 payload → 導到對應頁。

## What I already know（探索結論）

- 後端 `onTaskUpdated`（`functions/src/triggers/onTaskUpdated.ts:121`）已送 data payload
  `{ type:'task_ready', repoId, taskId }`（經 `tools/notify.ts`）。**唯一的通知種類就是 task_ready；目前沒有任何 Daily 類型通知。後端不需改。**
- 背景點擊 / 冷啟動已正確：`push_messaging.dart` 的 `_handleTap(RemoteMessage)` 解析
  `repoId`+`taskId` → `goTaskDetails`，否則 `goNotify`。
- **破口＝前景**：前景訊息用本地通知重畫，但
  1. `show(payload: m.data['taskId'])` 只帶 `taskId`、**沒帶 repoId**（`push_messaging.dart:54-58`）；
  2. 本地通知 `onTap` 寫死 `(_) => _navigation?.goNotify()`（`push_messaging.dart:44`），**無視 payload**。
  → 前景點擊一律掉到 `NotifyScreen`。
- `LocalNotificationsService.show(payload:)` 與 `init(onTap: (String? payload))` 的管線已存在
  （`local_notifications.dart`），payload 是單一字串，可直接利用。
- 導航方法齊全：`NavigationService.goTaskDetails(repoId, taskId)` / `goDaily(repoId)` / `goNotify()`。

## Requirements

- 前景通知重畫時，payload 帶完整路由資訊（至少 `repoId`+`taskId`，含 `type`）。
- 本地通知 `onTap` 改為解析 payload → 有 `repoId`+`taskId` 就 `goTaskDetails`，否則 `goNotify`。
- 抽一個**純函式**做「payload(字串/Map) → 路由決定」，讓背景 `_handleTap` 與前景 onTap 共用同一套邏輯，並可單元測試。
- 背景 / 冷啟動既有行為不退步（仍導到任務頁）。

## Acceptance Criteria

- [ ] 前景收到 task_ready 通知 → 點擊 → 進到該任務詳情頁（不再是 NotifyScreen）。
- [ ] 背景 / 冷啟動點擊行為不變（仍進任務詳情頁）。
- [ ] payload 缺 repoId/taskId 或無法解析 → 安全 fallback 到 `/notify`，不崩潰。
- [ ] 路由決定純函式有單元測試（task_ready 正常、缺欄位 fallback、壞字串 fallback）。
- [ ] `flutter analyze` 改動檔 0/0；`flutter test` 全綠。

## Definition of Done

- 單元測試覆蓋路由決定函式；analyze/test 綠。
- 模擬器 live 手測（亮/暗）：前景點擊導頁正確。
- 不改後端、不新增相依。

## Out of Scope

- 後端 payload / 通知種類不動。
- 不無中生有 Daily 推播（目前沒有 daily 通知；路由可依 type 預留分支但不接 sender）。
- 不重做 NotifyScreen 視覺（維持為 fallback 落地頁）。

## Decision (ADR-lite)

**Context**: demo 日，求穩；目前唯一通知種類是 task_ready，無 daily 通知。
**Decision**: 採最小方案——路由決定只看 `repoId`+`taskId`（有就導任務頁、否則 fallback `/notify`），
**不**做 `type` 分流 / daily 預留分支。
**Consequences**: 改動面最小、最不易出包；未來若加 daily 推播再擴成 type 分流即可。

## Technical Notes

- 改動集中在 `lib/services/push_messaging.dart`；payload 編碼可用 JSON（`dart:convert`）或分隔字串。
- 測試 seam：把「data map → route intent」抽成純函式（可放 push_messaging.dart 或小 helper），對它寫 test。
- 相關檔：`lib/services/local_notifications.dart`、`lib/services/navigation.dart`、
  `lib/views/notify/notify_screen.dart`、`functions/src/triggers/onTaskUpdated.ts`（參考，不改）。
- 此區為廷煥 FCM task（06-03）範圍，非他人進行中檔案。
