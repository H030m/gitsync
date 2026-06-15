# stats stale-while-revalidate cache

## 問題

每次點進「統計」頁都會先轉圈一下才出現內容。`/repos/:repoId/stats` 用 `CustomTransitionPage`
（go_router push，`lib/router/app_router.dart:155-166`），每次導頁都重建 `StatsViewPage`，
其 `ChangeNotifierProxyProvider2.create` 每次造出全新的 `StatsViewModel`，建構子設
`_commitsLoading=true` 並呼叫 `_loadAllCommits()` → 每次從零抓 all-history commits → 轉圈。
VM 內的 in-memory 快取隨 VM 一起被丟棄。

## 目標

進入統計頁的主 spinner（`commitsLoading`，貢獻度 + 進度表兩 tab 共用）只在「該 session 第一次」
出現。第二次以後進入立即顯示上次資料（不轉圈），背景靜默 revalidate，抓到新資料後就地更新。

## 方案

在 `StatsViewModel` 加 repoId-keyed 的 `static` commit 快取（生命週期長於 VM）：

1. `static final Map<String, List<Commit>> _commitCache = {}`。
2. 建構子：命中快取則同步種子 `_allCommits` / `_authorGroups` 並設 `_commitsLoading=false`
   （不轉圈），然後一律呼叫 `_loadAllCommits()` 背景刷新。
3. `_loadAllCommits()`：成功寫回快取；失敗時保留種子的舊資料（只有完全沒資料才退成空）。
4. `@visibleForTesting static void debugClearCommitCache()` 供測試重置，避免 static 跨測試汙染。

## 範圍外

- 不做跨 App 重啟的持久化（in-memory static 已滿足同 session「第二次以後」需求，且免新增相依）。
- 不快取逐人 AI 摘要（點開才 lazy 載入，不在進入路徑）。
- 不動路由 / UI widget / fake backend。

## 驗收

- `flutter analyze` 0/0；`flutter test` 全綠。
- 模擬器 live 手測（亮 + 暗）：第一次進轉圈一次；退出再進**無 spinner**、直接顯示上次圓餅/進度表，
  資料有變則短暫後就地更新。

## 動到的檔案

- `lib/view_models/stats_vm.dart`（主要）
- `test/stats_vm_test.dart`、`test/stats_view_test.dart`（setUp 清快取 + 可選 stale-seed 測試）
