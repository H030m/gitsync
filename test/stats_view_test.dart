import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/view_models/members_vm.dart';
import 'package:gitsync/view_models/tasks_board_vm.dart';
import 'package:gitsync/views/stats/stats_view_page.dart';

// Widget test: StatsViewPage renders the two prototype tabs (貢獻度 / 進度表)
// against the fake backend. The page wires StatsViewModel via
// ChangeNotifierProxyProvider2, so the harness only supplies the two upstream
// VMs (tasks + members) — no commits (the prototype has none).
Widget _harness() {
  const repoId = DummyData.demoRepoId;
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => TasksBoardViewModel(repoId: repoId)),
        ChangeNotifierProvider(create: (_) => MembersViewModel(repoId: repoId)),
      ],
      child: const StatsViewPage(repoId: repoId),
    ),
  );
}

void main() {
  testWidgets('renders both tabs; pie legend shows %, progress expands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Both tabs present.
    expect(find.text('貢獻度'), findsWidgets);
    expect(find.text('進度表'), findsOneWidget);

    // Tab 1 defaults to the commit basis → its caption is the all-commit one.
    expect(find.text('全部 commit 累計的貢獻度'), findsOneWidget);
    expect(find.text('已完成的任務累計的貢獻度'), findsNothing);

    // Toggle to the 任務 (task) basis → caption switches; legend shows the
    // done-task percentage (the only done task is demo-user-001's → 100%).
    await tester.tap(find.text('任務'));
    await tester.pumpAndSettle();

    expect(find.text('已完成的任務累計的貢獻度'), findsOneWidget);
    expect(find.text('全部 commit 累計的貢獻度'), findsNothing);
    expect(
      find.textContaining('100%'),
      findsWidgets,
      reason: 'legend chip should show the contribution percentage',
    );

    // Switch to Tab 2 (進度表).
    await tester.tap(find.text('進度表'));
    await tester.pumpAndSettle();

    expect(find.text('每個人當前未完成任務的進度'), findsOneWidget);
    expect(find.text('詳細情形'), findsWidgets);

    // The done task title is hidden until 詳細情形 is expanded.
    const doneTitle = 'Set up Flutter project skeleton';
    expect(find.text(doneTitle), findsNothing);

    // Expand the first 詳細情形 toggle (demo-user-001, the only assignee with a
    // done task) and verify the done task is shown struck-through.
    await tester.tap(find.text('詳細情形').first);
    await tester.pumpAndSettle();

    final doneText = tester.widget<Text>(find.text(doneTitle));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });
}
