# board row: drop status circle, avatar to left

## 問題 / 需求

團隊回饋手機版任務看板（收合式清單）每列左側的狀態圈圈不必要也不好看——既然長按整列就能換狀態，圈圈多餘。要拿掉它，並把右邊的負責人頭像移到左邊，最後一列＝「頭像(左) + 標題」。

## 方案

只動 `lib/views/tasks/tasks_board_page.dart` 的 `_SectionTaskRow`（窄螢幕收合清單）：
- Row 改為 `_AssigneeCircle`(左) → 間距 → `Expanded(標題)`。
- 移除前導狀態圈圈 `InkResponse`（radio_button_unchecked/check_circle）與右側原頭像。
- 移除只服務圈圈的 `_markDone` 方法與 `isDone` 區域變數。
- 保留 `onTap`→詳情頁、`onLongPress`→`showStatusPicker`（換狀態唯一入口）。
- 未指派任務沿用 `_AssigneeCircle` 既有灰色佔位圈，保標題左緣對齊；`_AssigneeCircle` 不改。

## 範圍外

- 寬螢幕三欄 kanban 卡片與拖拉換狀態不動；section header/收合/詳情頁/狀態 sheet 不動。
- 不刪 `updateStatus`（拖拉與 picker 仍用）。

## 驗收

- 移除 `test/tasks_board_test.dart` 的「tapping a row's circle marks the task done」測試；
  長按 picker 與點列導頁測試維持綠。
- `flutter analyze` 改動檔 0/0；`flutter test` 全綠。
- 模擬器手測（亮+暗）：每列只剩頭像(左)+標題、無圈圈；點列進詳情、長按換狀態正常。

## 動到的檔案

- `lib/views/tasks/tasks_board_page.dart`
- `test/tasks_board_test.dart`
