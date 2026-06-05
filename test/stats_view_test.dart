import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/view_models/commits_vm.dart';
import 'package:gitsync/view_models/members_vm.dart';
import 'package:gitsync/view_models/tasks_board_vm.dart';
import 'package:gitsync/views/stats/stats_view_page.dart';

// Smoke test: StatsViewPage renders its four cards against the fake backend.
// The page wires StatsViewModel via ChangeNotifierProxyProvider3, so the
// harness only needs to supply the three upstream VMs.
Widget _harness() {
  const repoId = DummyData.demoRepoId;
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TasksBoardViewModel(repoId: repoId)),
        ChangeNotifierProvider(create: (_) => CommitsViewModel(repoId: repoId)),
        ChangeNotifierProvider(create: (_) => MembersViewModel(repoId: repoId)),
      ],
      child: const StatsViewPage(repoId: repoId),
    ),
  );
}

void main() {
  testWidgets('Stats page renders all four chart cards', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Task status'), findsOneWidget);
    expect(find.text('Commits per author'), findsOneWidget);
    expect(find.text('Daily commits (last 14 days)'), findsOneWidget);
    expect(find.text('Member load'), findsOneWidget);

    // CommitsViewModel eagerly fetches the branch graph (a fake-latency
    // Future) on construction; the Stats page never renders it, so
    // pumpAndSettle returns before that timer fires. Drain it here so the
    // test doesn't fail on a pending Timer at teardown.
    await tester.pump(const Duration(seconds: 1));
  });
}
