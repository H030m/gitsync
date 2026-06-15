import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/l10n/app_locale.dart';
import 'package:gitsync/models/discord_digest.dart';
import 'package:gitsync/repositories/fake/fake_discord_digest_repo.dart';
import 'package:gitsync/view_models/ask_repo_vm.dart';
import 'package:gitsync/view_models/commits_vm.dart';
import 'package:gitsync/view_models/daily_report_vm.dart';
import 'package:gitsync/view_models/discord_messages_vm.dart';
import 'package:gitsync/view_models/intel_range_vm.dart';
import 'package:gitsync/views/daily/daily_view_page.dart';

import '_helpers/locale.dart';

// Drives the real DailyViewPage against the fake backend, proving that after the
// 06-15 merge (D1) each day's Discord digest renders INLINE inside that day's
// unified card (aligned by date with the AI report), rather than in a separate
// Discord tab / digest panel.
//
// The widget tests look for English UI strings (e.g. the `Discord digest`
// sub-heading), so `_harness()` pins the locale to English via
// [pinLocale] (production default is Traditional Chinese since `5b7e562`).

const _repoId = DummyData.demoRepoId;

Widget _harness() {
  return pinLocale(
    AppLocale.en,
    child: MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CommitsViewModel(repoId: _repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => DiscordMessagesViewModel(repoId: _repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => DailyReportViewModel(repoId: _repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => AskRepoViewModel(repoId: _repoId),
          ),
          ChangeNotifierProvider(create: (_) => IntelRangeViewModel()),
        ],
        child: const DailyViewPage(repoId: _repoId),
      ),
    ),
  );
}

// Seeds an explicit digest doc for [date] (YYYY-MM-DD) in the fake repo.
DiscordDigest _seed(String date) {
  final digest = DiscordDigest(
    date: date,
    markdown: '**Digest for $date**',
    messageCount: 3,
  );
  FakeDiscordDigestRepository().seedDigest(_repoId, digest);
  return digest;
}

void main() {
  // The fake digest repo is a process-wide singleton; start each test clean.
  setUp(() => FakeDiscordDigestRepository().reset());
  tearDown(() => FakeDiscordDigestRepository().reset());

  // Pumps the page, scopes the shared range over [start]..[end] (so the report
  // produces a day card per day, and the digest VM shows those days' digests),
  // and returns the Discord VM. After the 06-15 merge the day cards render
  // directly in the tab's ListView (the collapsible reports panel was removed
  // when the chat moved to a full-screen route), so there's no panel to expand.
  Future<DiscordMessagesViewModel> openRange(
    WidgetTester tester,
    DateTime start,
    DateTime end,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(DailyViewPage));
    ctx.read<IntelRangeViewModel>().setRange(
      DateTimeRange(start: start, end: end),
    );
    await tester.pumpAndSettle();

    return ctx.read<DiscordMessagesViewModel>();
  }

  // Expands a non-today day card (collapsed by default) via its date header so
  // its inline Discord-digest section becomes reachable.
  Future<void> expandDay(WidgetTester tester, String dayKey) async {
    await tester.tap(find.text(dayKey));
    await tester.pumpAndSettle();
  }

  testWidgets('each day with a digest shows it inline under the report', (
    tester,
  ) async {
    _seed('2026-06-03');
    _seed('2026-06-04');

    final vm = await openRange(
      tester,
      DateTime(2026, 6, 3),
      DateTime(2026, 6, 5),
    );
    await expandDay(tester, '2026-06-03');
    await expandDay(tester, '2026-06-04');

    // Newest first, only days that HAVE a digest carry one.
    expect(vm.digests.map((d) => d.date).toList(), [
      '2026-06-04',
      '2026-06-03',
    ]);

    // Both seeded digests render inline (their markdown is visible). The
    // digest-less 6/5 day card shows no digest markdown.
    expect(find.textContaining('Digest for 2026-06-04'), findsOneWidget);
    expect(find.textContaining('Digest for 2026-06-03'), findsOneWidget);
    expect(find.textContaining('Digest for 2026-06-05'), findsNothing);

    // The inline "Discord digest" sub-heading appears once per digest day.
    expect(find.text('Discord digest'), findsNWidgets(2));
  });

  testWidgets(
    'a window ending on a digest-less day still shows earlier digests',
    (tester) async {
      // The motivating regression: only older days have digests; the window ends
      // on a digest-less day. The earlier days' digests must still surface.
      _seed('2026-06-03');
      _seed('2026-06-04');

      final vm = await openRange(
        tester,
        DateTime(2026, 6, 3),
        DateTime(2026, 6, 5),
      );
      await expandDay(tester, '2026-06-03');
      await expandDay(tester, '2026-06-04');

      expect(find.byType(DailyViewPage), findsOneWidget);
      expect(vm.digests.length, 2);
      expect(find.textContaining('Digest for 2026-06-04'), findsOneWidget);
      expect(find.textContaining('Digest for 2026-06-03'), findsOneWidget);
    },
  );

}
