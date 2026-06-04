import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/view_models/commits_vm.dart';
import 'package:gitsync/view_models/daily_brief_vm.dart';
import 'package:gitsync/view_models/daily_report_vm.dart';
import 'package:gitsync/view_models/discord_chat_vm.dart';
import 'package:gitsync/view_models/discord_messages_vm.dart';
import 'package:gitsync/views/daily/daily_view_page.dart';

// Renders the real Commits tab (tree map) against the fake backend, drives the
// range filter and the tap-a-commit → AI work summary sheet.
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
      ],
      child: const DailyViewPage(repoId: repoId),
    ),
  );
}

Future<void> _openCommitsTab(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Commits'));
  await tester.pumpAndSettle();
}

/// The branch graph is the default visualization — these tree-map tests
/// flip the toggle to the per-author view first.
Future<void> _switchToAuthorView(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.person_outline));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Commits tab renders the tree map with day headers',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);
    await _switchToAuthorView(tester);

    expect(find.text('Commit map'), findsOneWidget);
    // All five dummy commits are on screen, grouped under day headers.
    expect(
        find.text('TaskBoard drag-and-drop between columns'), findsOneWidget);
    expect(find.text('Wire up GitHub OAuth provider in AuthService'),
        findsOneWidget);
    // The commits span multiple days → at least two day-header rows. (The
    // exact count depends on the wall clock vs the staggered dummy offsets.)
    final headerPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && headerPattern.hasMatch(w.data ?? '')),
      findsAtLeastNWidgets(2),
    );
  });

  testWidgets('tapping a commit opens the sheet with an AI work summary',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);
    await _switchToAuthorView(tester);

    await tester.tap(find.text('TaskBoard drag-and-drop between columns'));
    await tester.pumpAndSettle();

    expect(find.text('AI work summary'), findsOneWidget);
    // The fake explainCommit returns markdown grounded in the commit.
    expect(
      find.textContaining('Kanban columns', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('range filter narrows the map to the picked days',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);
    await _switchToAuthorView(tester);
    final vm = tester
        .element(find.text('Commit map'))
        .read<CommitsViewModel>();

    // Filter to yesterday..today: the freshest commit (now − 2h, which may
    // straddle midnight) stays; the oldest (now − 2d5h) always falls outside.
    final now = DateTime.now();
    vm.setRange(now.subtract(const Duration(days: 1)), now);
    await tester.pumpAndSettle();

    expect(
        find.text('TaskBoard drag-and-drop between columns'), findsOneWidget);
    expect(find.text('Add MVVM skeleton and Firebase config placeholders'),
        findsNothing);

    // Clearing goes back to the full recent list.
    vm.clearRange();
    await tester.pumpAndSettle();
    expect(find.text('Add MVVM skeleton and Firebase config placeholders'),
        findsOneWidget);
  });

  testWidgets('branch graph (default view) shows topology, tips and PR badge',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);

    // The fake getCommitGraph topology: merge of feature/daily-report (#7).
    expect(
      find.text('Merge pull request #7 from demo/feature-daily-report'),
      findsOneWidget,
    );
    expect(find.text('#7'), findsOneWidget); // merge node's PR badge
    expect(find.text('main'), findsOneWidget); // branch tip labels
    expect(find.text('feature/daily-report'), findsOneWidget);

    // Tap-to-explain works from the branch view too.
    await tester.tap(find.text('feat(daily): wire report card'));
    await tester.pumpAndSettle();
    expect(find.text('AI work summary'), findsOneWidget);
  });

  testWidgets('Recent 50 reset chip appears with a range and clears it',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);
    final vm = tester
        .element(find.text('Commit map'))
        .read<CommitsViewModel>();

    // No range → the filter button itself reads "Recent 50", no reset chip.
    expect(find.byIcon(Icons.restore), findsNothing);

    final now = DateTime.now();
    vm.setRange(now.subtract(const Duration(days: 1)), now);
    await tester.pumpAndSettle();

    // Reset affordance is one tap away and goes back to the recent stream.
    expect(find.byIcon(Icons.restore), findsOneWidget);
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    expect(vm.hasRange, isFalse);
  });
}
