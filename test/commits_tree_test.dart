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

void main() {
  testWidgets('Commits tab renders the tree map with day headers',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openCommitsTab(tester);

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
}
