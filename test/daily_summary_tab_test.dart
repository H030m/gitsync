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

    expect(find.text('Daily summary'), findsOneWidget);
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
}
