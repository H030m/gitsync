# Bottom Nav Focus Slide Animation

## Goal

將 Flutter app 的 bottom navigation bar 從原生 `NavigationBar` 改為自訂元件，加入 prototype 中的 sliding pill indicator 效果 — 一個圓角背景會隨 active tab 滑順水平移動。

## What I already know

* Prototype (GitSync_Figma) 使用 CSS `transition-all duration-300 ease-out` 實現 pill 滑動
* Prototype pill 規格：`w-16 h-14 rounded-full`，定位用 `left: calc(${activeIndex * 25}% + 12.5% - 32px)`
* Flutter 端目前在 `lib/views/shell/repo_shell.dart` 使用原生 `NavigationBar` (Material 3)
* 有 4 個 tab：Tasks / Daily / Stats / Settings
* 使用 GoRouter，active index 由 URL path 推導
* Prototype 的 pill 背景色為 `colors.borderLight`

## Decision (ADR-lite)

**Context**: 原生 M3 NavigationBar 的 indicator 是淡入淡出，不支援跨 tab 滑動動畫
**Decision**: 自訂 bottom nav widget，用 `AnimatedAlign` + `Stack` 實現 sliding pill
**Consequences**: 需自行維護 bottom nav 樣式，但獲得完全的動畫控制

## Requirements

* 自訂 bottom nav 取代原生 `NavigationBar`
* Pill 形狀：膠囊型（全圓角），包住 icon + label 區域
* Pill indicator 隨 tab 切換水平滑動，使用 `AnimatedAlign`
* 動畫曲線：`Curves.easeOut`，duration 300ms（與 prototype 一致）
* 保留現有 4 個 tab 的 icon + label 配置
* Active tab icon/label 使用 `colorScheme.primary`（light）/ accent 色（dark）
* Inactive tab 使用 `colorScheme.onSurfaceVariant`
* Pill 背景色使用 `colorScheme.surfaceContainerHighest` 或相近淺色
* Bottom nav 高度 80px，背景色 `colorScheme.surfaceContainer`
* 與現有 GoRouter 導航邏輯相容（`_selectedIndex` 邏輯不變）

## Acceptance Criteria

* [ ] 切換 tab 時 pill 背景平滑滑動到目標 tab 下方
* [ ] 動畫不卡頓（60fps）
* [ ] 保留現有路由功能，不影響導航行為
* [ ] Light/dark mode 下視覺正確

## Definition of Done

* Lint / typecheck green
* 手動測試四個 tab 切換皆流暢

## Out of Scope

* 手勢滑動切換 tab
* 自訂動畫曲線選項
* Bottom nav 的 badge/notification dot

## Technical Approach

1. 在 `repo_shell.dart` 中新增 `_SlidingBottomNav` private widget
2. 使用 `Stack` 疊加：底層 pill（`AnimatedAlign`）+ 上層 tab buttons（`Row`）
3. `AnimatedAlign` 的 `alignment` 根據 `selectedIndex` 計算水平位置
4. 每個 tab button 用 `Expanded` 等分寬度，icon + label 垂直排列
5. Active/inactive 顏色從 `Theme.of(context).colorScheme` 取得

## Technical Notes

* 檔案影響範圍：`lib/views/shell/repo_shell.dart`（僅此一檔）
* Prototype 參考：`GitSync_Figma/src/app/components/BottomNav.tsx`
* Theme 顏色來源：`lib/theme/app_colors.dart` + `lib/theme/app_theme.dart`
* Design tokens：`lib/theme/app_dimens.dart`（radius / spacing）
* `AnimatedAlign` 自帶 implicit animation，不需手動管理 `AnimationController`
