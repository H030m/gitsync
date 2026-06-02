# 接上 FCM 通知：initialize 接線 + web service worker/VAPID

> **狀態：TODO（planning，尚未啟動）**。記錄於 2026-06-03，動態分派 live 驗證時發現
> 通知收不到。動態分派本身已可運作，這是錦上添花的後續工作。

## Goal

讓 `onTaskUpdated` 自動分派下游後，被指派的 member 真的**收到 FCM 推播通知**。
目前後端已會發（`tools/notify.ts` `notifyAssignee`），但 log 一直是
`notifyAssignee: no fcmToken, skipping` —— 因為 `users/{uid}.fcmToken` 從來沒被寫進去。

## 診斷（已查證，repo inspection 2026-06-03）

**根因（與平台無關）：`PushMessagingService.initialize()` 從沒被呼叫。**
* `lib/services/push_messaging.dart` — `initialize({userId})` 會 `requestPermission` →
  `getToken()` → `userRepository.updateFcmToken(uid, token)`，邏輯完整。
* 但 `lib/main.dart:44` 只把它註冊成 `Provider<PushMessagingService>(create:...)`，
  **全專案沒有任何地方 call `.initialize(userId:...)`** → token 永遠沒被取得/寫入。
* ⇒ 即使在手機上跑也收不到通知，不是只有 web。

**Web 額外門檻（即使 initialize 接好）：**
* `web/` 沒有 `firebase-messaging-sw.js`（FCM web 必須的 service worker）。
* `push_messaging.dart:38` 的 `getToken()` 沒帶 `vapidKey` —— web 取 token 必填，
  要去 Firebase Console → Cloud Messaging → Web Push certificates 拿 VAPID key。
* 需 HTTPS + 瀏覽器通知權限。

## 待釐清（啟動前 brainstorm）

* [平台] demo 通知要跑手機、web、還是兩者？（決定要不要做 web service worker/VAPID）
* [替代方案] 是否改用 **app 內 Firestore 監聽「assigneeId == 我」→ 跳 in-app 提示**，
  完全不碰 FCM/web sw？對 demo 可能更穩、更省事。值得跟推播二選一或併行評估。

## 可能的 Requirements（待 brainstorm 收斂）

* 共通：登入成功後呼叫 `PushMessagingService.initialize(uid)`（補上漏掉的接線）；
  處理權限被拒的情況。
* Web（若需要）：加 `web/firebase-messaging-sw.js`、`getToken(vapidKey: <key>)`。
* 前端 foreground / tap 行為目前是 `debugPrint` placeholder → 視需要補成 in-app banner + 導頁。

## Out of Scope（本 TODO 不含、已完成）

* 後端發送邏輯（`notifyAssignee` 已實作且運作中）。
* 動態分派本身（`onTaskUpdated` + `assignTaskFlow` 已 live 驗證成功）。

## Technical Notes

* 後端只認 `users/{uid}.fcmToken`；只要前端把 token 寫進去，現有發送就會生效。
* 課程限制：FCM 屬 Firebase、可用；web 設定較繁，手機最單純（見團隊記憶 final-demo 限制）。
