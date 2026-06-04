import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/view_models/commits_vm.dart';
import 'package:gitsync/view_models/daily_brief_vm.dart';
import 'package:gitsync/view_models/daily_report_vm.dart';
import 'package:gitsync/view_models/discord_chat_vm.dart';
import 'package:gitsync/view_models/discord_messages_vm.dart';
import 'package:gitsync/view_models/intel_range_vm.dart';
import 'package:gitsync/views/daily/daily_view_page.dart';

// Renders the real DailyViewPage (Summary tab) against the fake backend and
// drives the "ask AI about today" chat, verifying the intelligence-hub UI wires
// up end-to-end.
Widget _harness() {
  const repoId = DummyData.demoRepoId;
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CommitsViewModel(repoId: repoId)),
        ChangeNotifierProvider(
            create: (_) => DiscordMessagesViewModel(repoId: repoId)),
        ChangeNotifierProvider(
            create: (_) => DiscordChatViewModel(repoId: repoId)),
        ChangeNotifierProvider(
            create: (_) => DailyReportViewModel(repoId: repoId)),
        ChangeNotifierProvider(
            create: (_) => DailyBriefChatViewModel(repoId: repoId)),
        ChangeNotifierProvider(create: (_) => IntelRangeViewModel()),
      ],
      child: const DailyViewPage(repoId: repoId),
    ),
  );
}

void main() {
  testWidgets('Summary tab shows the daily report sections', (tester) async {
    // Tall viewport so every lazily-built section renders without scrolling.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Today's per-day card is expanded by default, showing the full report.
    expect(find.textContaining('Today'), findsWidgets);
    expect(find.textContaining('Sprint 1 skeleton merged'), findsOneWidget);
    expect(find.text('Commit rollup'), findsOneWidget);
    expect(find.text('Contributions'), findsOneWidget);
    expect(find.text('Ask AI about today'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Ask AI about today…'),
      findsOneWidget,
    );
  });

  testWidgets('asking a question adds an AI answer with source commits',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final field = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'Ask AI about today…',
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, 'OAuth 進度?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    // The user's question and an AI source panel are now on screen.
    expect(find.text('OAuth 進度?'), findsOneWidget);
    expect(find.textContaining('Source commits'), findsOneWidget);
  });

  testWidgets('a multi-day range shows one collapsible card per day',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Pick a 3-day range ending today via the shared range notifier.
    final report =
        tester.element(find.byType(DailyViewPage)).read<DailyReportViewModel>();
    final intel =
        tester.element(find.byType(DailyViewPage)).read<IntelRangeViewModel>();
    final now = DateTime.now();
    intel.setRange(DateTimeRange(
      start: now.subtract(const Duration(days: 2)),
      end: now,
    ));
    await tester.pumpAndSettle();

    // The report VM took the range → exactly 3 day cards.
    expect(report.rangeDays.length, 3);
    expect(find.byKey(ValueKey(DailyReportViewModel.dayKeyOf(now))),
        findsOneWidget);

    // Today's card is expanded — the full body (Regenerate + sub-cards) shows.
    expect(find.widgetWithText(FilledButton, 'Regenerate'), findsOneWidget);
    expect(find.text('Commit rollup'), findsOneWidget);

    // Tap the header to collapse; the full body disappears (the one-line
    // summary preview remains in the collapsed header).
    await tester.tap(find.textContaining('Today ·'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Regenerate'), findsNothing);
    expect(find.text('Commit rollup'), findsNothing);

    // Drain the fake Discord backfill timer (intel.setRange → discord.setRange).
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a day with no report offers a generate button that fires '
      'summarizeDay for that day', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final report =
        tester.element(find.byType(DailyViewPage)).read<DailyReportViewModel>();
    final intel =
        tester.element(find.byType(DailyViewPage)).read<IntelRangeViewModel>();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    // Range = yesterday..yesterday: the fake has no report for it.
    intel.setRange(DateTimeRange(start: yesterday, end: yesterday));
    await tester.pumpAndSettle();

    // A non-today card starts collapsed; expand it via its header.
    await tester.tap(find.text(DailyReportViewModel.dayKeyOf(yesterday)));
    await tester.pumpAndSettle();

    // The expanded card has no report → offers "產生日報".
    final generate = find.widgetWithText(FilledButton, '產生日報');
    expect(generate, findsOneWidget);

    // Tapping it drives the VM's per-day generation state.
    expect(report.isGeneratingDay(DailyReportViewModel.dayKeyOf(yesterday)),
        isFalse);
    await tester.tap(generate);
    await tester.pump();
    expect(report.isGeneratingDay(DailyReportViewModel.dayKeyOf(yesterday)),
        isTrue);
    await tester.pumpAndSettle();
    expect(report.isGeneratingDay(DailyReportViewModel.dayKeyOf(yesterday)),
        isFalse);

    // Drain the fake Discord backfill timer (intel.setRange → discord.setRange).
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the shared range picker propagates to all three tabs and '
      'clearing resets them', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(DailyViewPage));
    final intel = ctx.read<IntelRangeViewModel>();
    final report = ctx.read<DailyReportViewModel>();
    final commits = ctx.read<CommitsViewModel>();
    final discord = ctx.read<DiscordMessagesViewModel>();

    expect(commits.hasRange, isFalse);
    expect(report.hasRange, isFalse);

    final now = DateTime.now();
    intel.setRange(DateTimeRange(
      start: now.subtract(const Duration(days: 2)),
      end: now,
    ));
    // Pump once (not settle) so the in-flight Discord backfill is observable:
    // intel.setRange → discord.setRange flips settingRange before it resolves,
    // proving the shared range reached the Discord VM too (D2 side effect).
    await tester.pump();
    expect(discord.settingRange, isTrue);
    await tester.pumpAndSettle();

    // Commits + report VMs both took the shared range.
    expect(commits.hasRange, isTrue);
    expect(report.hasRange, isTrue);

    // Let the SET backfill's delayed timer resolve so the Discord VM goes idle
    // again — a clean baseline for the clear assertion below.
    await tester.pump(const Duration(seconds: 1));
    expect(discord.settingRange, isFalse);

    // Clearing resets the other three tabs to their default…
    intel.clear();
    await tester.pump();
    expect(commits.hasRange, isFalse);
    expect(report.hasRange, isFalse);
    // …but must NOT touch the Discord VM: clearing the shared *view* scope must
    // not overwrite the team's saved backfill range (setRange == a persistent
    // setDiscordRange write). settingRange staying false proves clear() never
    // called discord.setRange (which would flip it true synchronously).
    expect(discord.settingRange, isFalse);

    // Drain any remaining fake-backend delayed timers so the harness doesn't
    // flag a pending timer at dispose.
    await tester.pump(const Duration(seconds: 1));
  });
}
