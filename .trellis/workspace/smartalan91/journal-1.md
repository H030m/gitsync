# Journal - smartalan91 (Part 1)

> AI development session journal
> Started: 2026-06-10

---



## Session 1: FCM notifications: live e2e verified, permission-feedback fix, PR #38 to main

**Date**: 2026-06-12
**Task**: FCM notifications: live e2e verified, permission-feedback fix, PR #38 to main
**Branch**: `feature/foreground-notifications`

### Summary

Took over 06-03-wire-fcm-notifications from opal. Reproduced the reported 'test notification does nothing': clean install works; root cause is silent failure when POST_NOTIFICATIONS denied. Fixed with ensurePermission() + localized SnackBar hint; verified both paths on emulator. Completed live e2e on Android (fcmToken write, done-task auto-notify: foreground redraw / background tray / tap routing / zh-Hant per-locale copy). Merged latest develop (no conflicts), analyze 0 warn, tests 79/79. PR #38 merged into main with teammate approval; develop still needs back-merge from main. Captured specs (notification permission feedback convention, google-services.json placeholder) and SETUP 5.10.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0d4ef9a` | (see git log) |
| `7286a44` | (see git log) |
| `bd4a703` | (see git log) |
| `e1363cd` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Mobile board redesign: collapsible status sections

**Date**: 2026-06-13
**Task**: Mobile board redesign: collapsible status sections
**Branch**: `feature/mobile-board-sections`

### Summary

Replaced the phone-width kanban (horizontally scrolling 200dp columns) with a TickTick-style vertical list of three collapsible status sections; rows open task details, circle-tap marks done (feeding the done->AI-assign->FCM demo chain). Wide kanban untouched. Removed the 2 stale red tests from the 06-12 card simplification and added 5 behavioral tests - suite 81/81 green. Captured the phone-board convention in component-guidelines.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `9470677` | (see git log) |
| `236419b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: Dual-entry task status editor

**Date**: 2026-06-13
**Task**: Dual-entry task status editor
**Branch**: `feature/mobile-board-sections`

### Summary

User acceptance of the section list surfaced a gap: the details-page status chip had always been read-only, so phones could only transition to done. Added a shared showStatusPicker bottom sheet with two entries (tappable details chip, section-row long-press); related chips stay read-only, existing behaviors unchanged. New details-page test harness; suite 85/85.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `931838a` | (see git log) |
| `931838a` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: Stats stale-while-revalidate commit cache

**Date**: 2026-06-15
**Task**: Stats stale-while-revalidate commit cache
**Branch**: `feature/stats-swr-cache`

### Summary

Cache all-history commits in a repoId-keyed static map on StatsViewModel so re-entering the Stats page seeds from cache (no spinner) and revalidates in the background; failed refresh keeps stale data. Added debugClearCommitCache() + setUp resets in both stats tests, +2 tests. analyze 0/0 on changed files, flutter test 100/100, emulator hand-verified no re-entry spinner.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `41ff343` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: Persist theme mode across web refresh

**Date**: 2026-06-15
**Task**: Persist theme mode across web refresh
**Branch**: `feature/persist-theme-mode`

### Summary

ThemeModeNotifier kept the theme only in memory, so F5 / fresh load reset to ThemeMode.system (appeared dark). Added SharedPreferences persistence mirroring LocaleNotifier: constructor _load()s stored value, setMode/toggle write it back (key theme_mode, value enum .name). Public API/provider wiring/UI unchanged, default stays system. analyze 0/0 on changed files, flutter test 104/104 (+4 new theme tests).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `71cbf3c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: Board row: drop status circle, avatar to left

**Date**: 2026-06-15
**Task**: Board row: drop status circle, avatar to left
**Branch**: `feature/board-row-avatar-left`

### Summary

Removed the leading status circle from _SectionTaskRow on the mobile sectioned board and moved the assignee avatar from the trailing to the leading edge (avatar + title). Dropped the circle-only _markDone helper and isDone local; long-press still opens the status picker, tap still navigates to details. Removed the obsolete circle test. analyze 0/0 on changed files, tasks_board_test 11/11. Note: daily_* tests already red on develop from the chat/daily refactor merge (not this change).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `802ceed` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 7: Deep-link foreground notification taps to the task

**Date**: 2026-06-16
**Task**: Deep-link foreground notification taps to the task
**Branch**: `feature/notify-deeplink-foreground`

### Summary

Foreground FCM notification taps landed on the placeholder NotifyScreen because the redrawn local notification carried only taskId (no repoId) and its onTap was hardwired to goNotify(). Encode the full data map as JSON payload and route through two pure unit-tested helpers (taskRouteFromData, decodeNotificationPayload) shared by foreground and background taps; valid repoId+taskId deep-links to the task, else /notify. No backend change. analyze 0/0 on changed files, flutter test 110/110 (+7 new).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1ba90b8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
