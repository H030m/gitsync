import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/locale_notifier.dart';
import 'app_locale.dart';

/// `context.l10n.someKey` returns the string for the current UI language.
/// Falls back to the default language when no [LocaleNotifier] is in the tree
/// (e.g. widget tests that pump a page in isolation), so callers never crash.
extension AppLocalizationsX on BuildContext {
  AppStrings get l10n {
    try {
      return AppStrings(watch<LocaleNotifier>().locale);
    } catch (_) {
      return const AppStrings(AppLocale.zhHant);
    }
  }
}

/// Hand-written string table for the two supported languages. One getter per
/// user-facing string; `_(en, zh)` picks by the active locale. Kept in one file
/// so both translations sit side by side.
class AppStrings {
  const AppStrings(this.locale);
  final AppLocale locale;

  String _(String en, String zh) => locale == AppLocale.en ? en : zh;

  // ---- Common ----
  String get cancel => _('Cancel', '取消');
  String get delete => _('Delete', '刪除');
  String get add => _('Add', '新增');
  String get remove => _('Remove', '移除');
  String get done => _('Done', '完成');
  String get view => _('View', '查看');

  // ---- Status ----
  String get statusTodo => _('To do', '待辦');
  String get statusInProgress => _('In progress', '進行中');
  String get statusDone => _('Done', '完成');

  // ---- Sign in ----
  String get appTagline =>
      _("Your team's repos, tasks, and daily activity in one place.",
          '在一個地方掌握團隊的 repo、任務與每日動態。');
  String get signInWithGitHub => _('Sign in with GitHub', '使用 GitHub 登入');
  String get signingIn => _('Signing in…', '登入中…');

  // ---- Repo list ----
  String get yourRepos => _('Your repos', '你的 Repo');
  String get noReposTitle => _('No repos yet', '還沒有 Repo');
  String get noReposMsg => _('Tap + to connect your first GitHub repository.',
      '點 + 連結你的第一個 GitHub repo。');
  String get notSignedIn => _('Not signed in', '尚未登入');
  String get removeRepoTitle => _('Remove repo?', '移除 Repo?');
  String removeRepoBody(String name) => _(
      'Remove $name? This deletes the repo and all its tasks/data. This cannot be undone.',
      '確定移除 $name?這會刪除該 repo 及其所有任務/資料,且無法復原。');
  String get removeRepoFailed => _('Failed to remove repo', '移除 repo 失敗');

  // ---- Tasks board ----
  String get tasksTitle => _('Tasks', '任務');
  String get boardTab => _('Board', '看板');
  String get graphTab => _('Graph', '關聯圖');
  String get emptyBoardTitle =>
      _('No project structure yet', '您還未輸入專案架構');
  String get emptyBoardMsg =>
      _('Tap the + button to add tasks.', '請點擊右下角 + 號來新增任務');
  String updateStatusFailed(Object e) =>
      _('Failed to update status: $e', '更新狀態失敗:$e');

  // ---- Add task ----
  String get addTaskTitle => _('Add task', '新增任務');
  String get manual => _('Manual', '手動');
  String get aiBreakdown => _('AI breakdown', 'AI 拆解');
  String get taskTitleLabel => _('Task title', '任務標題');
  String get descriptionOptional => _('Description (optional)', '描述(選填)');
  String get addingTask => _('Adding…', '新增中…');
  String get projectSpec => _('Project spec', '專案規格');
  String get projectSpecHint => _(
      'Paste your SPEC.md (Markdown) here — the AI breaks it into a high-level TODO list.',
      '把你的 SPEC.md(Markdown)貼在這裡 —— AI 會拆成一份高層次的任務清單。');
  String get breakDownWithAI => _('Break down with AI', '用 AI 拆解');
  String get breakingDown => _('Breaking down…', '拆解中…');
  String generatedNSubtasks(int n) =>
      _('Generated $n subtasks', '產生了 $n 個子任務');
  String get taskAdded => _('Task added.', '已新增任務。');

  // ---- Task details ----
  String get taskDetailsTitle => _('Task details', '任務細節');
  String get deleteTaskTooltip => _('Delete task', '刪除任務');
  String get assignee => _('Assignee', '認領者');
  String get assign => _('Assign', '指派');
  String get change => _('Change', '變更');
  String get unassigned => _('Unassigned', '未指派');
  String get descriptionSection => _('Description', '任務描述');
  String get implementationDetails => _('Implementation details', '實作細節');
  String get subtasks => _('Subtasks', '子任務');
  String get dependsOn => _('Depends on', '相依於');
  String get handoff => _('Handoff', '交接內容');
  String get generate => _('Generate', '產生');
  String get regenerate => _('Regenerate', '重新產生');
  String get noHandoffYet => _(
      'No handoff doc yet. It is generated automatically when this task\'s prerequisites are completed, or tap Generate.',
      '還沒有交接文件。會在前置任務完成時自動產生,或點「產生」。');
  String get assignToTitle => _('Assign to', '指派給');
  String get unassign => _('Unassign', '取消指派');
  String get importCollaborators =>
      _('Import collaborators from GitHub', '從 GitHub 匯入協作者');
  String get importCollaboratorsSub =>
      _('Adds teammates who already use GitSync', '加入已使用 GitSync 的隊友');
  String get noPrerequisites => _(
      'No prerequisites. Tap Add to choose a parent task.',
      '沒有前置任務。點「新增」選一個父任務。');
  String get addPrerequisite => _('Add a prerequisite', '新增前置任務');
  String get removePrerequisite => _('Remove prerequisite', '移除前置任務');
  String get noEligibleTasks => _('No eligible tasks to add.', '沒有可加入的任務。');
  String get deleteTaskQuestion => _('Delete task?', '刪除任務?');
  String deleteTaskBody(String title) => _(
      'Delete "$title"? Its prerequisites will be reconnected to the tasks that depend on it.',
      '確定刪除「$title」?它的前置任務會自動接到依賴它的任務上。');
  String get couldNotUpdateAssignee =>
      _('Could not update the assignee.', '無法更新負責人。');
  String get couldNotGenerateHandoff =>
      _('Could not generate the handoff doc.', '無法產生交接文件。');
  String get couldNotOpenLink => _('Could not open the link.', '無法開啟連結。');
  String get couldNotAddPrereq =>
      _('Could not add that prerequisite.', '無法新增該前置任務。');
  String get couldNotImport =>
      _('Could not import collaborators.', '無法匯入協作者。');
  String get importingCollaborators =>
      _('Importing GitHub collaborators…', '正在匯入 GitHub 協作者…');
  String importedSummary(int added, int already, int pending) => _(
      'Added $added member(s)${already > 0 ? ' · $already already in' : ''}${pending > 0 ? ' · $pending not signed in yet' : ''}. Reopen the picker to assign them.',
      '已加入 $added 位成員${already > 0 ? '・$already 位已在' : ''}${pending > 0 ? '・$pending 位尚未登入' : ''}。重新開啟選單即可指派。');

  // ---- Graph ----
  String get noTasksYet => _('No tasks yet', '還沒有任務');
  String get unlinked => _('Unlinked', '未連結');
  String get addTaskTooltip => _('Add task', '新增任務');
  String get openDetails => _('Open details', '開啟細節');
  String get linkFromHere => _('Link from here…', '從這裡連線…');
  String get dependencyAdded => _('Dependency added.', '已新增依賴。');
  String get cannotLink => _(
      "Can't link — it already exists or would create a cycle.",
      '無法連線 —— 已存在或會造成循環。');
  String linkTargetPrompt(String title) =>
      _('Tap the task that depends on "$title"', '點選依賴「$title」的任務');

  // ---- Notify ----
  String get notificationTitle => _('Notification', '通知');
  String get openedFromPush =>
      _('Opened from a push notification.', '從推播通知開啟。');
  String get backToRepos => _('Back to repos', '回到 Repo 列表');
  String newTaskAssigned(String title) =>
      _('New task assigned to you: $title', '有新任務指派給你:$title');

  // ---- Settings ----
  String get settingsTitle => _('Settings', '設定');
  String get appearance => _('Appearance', '外觀');
  String get language => _('Language', '語言');
  String get account => _('Account', '帳號');
  String get signOut => _('Sign out', '登出');
  String get themeSystem => _('System', '系統');
  String get themeLight => _('Light', '淺色');
  String get themeDark => _('Dark', '深色');
  String get backendFakeTitle =>
      _('Backend: FAKE (dummy data)', '後端:假資料(FAKE)');
  String get backendLiveTitle =>
      _('Backend: LIVE (Firebase)', '後端:正式(Firebase)');
  String get backendFakeBody => _(
      'No real Firebase / OpenAI / GitHub calls. Mutations live in memory and reset on restart. To switch: stop the app and re-run with `--dart-define=BACKEND=live`.',
      '不會呼叫真正的 Firebase / OpenAI / GitHub。所有變更只存在記憶體、重啟即重置。要切換:停止 app 並用 `--dart-define=BACKEND=live` 重跑。');
  String get backendLiveBody => _(
      'Hitting real Firebase project. Be careful with destructive actions.',
      '連到正式 Firebase 專案,執行破壞性操作請小心。');
}
