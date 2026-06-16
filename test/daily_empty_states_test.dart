import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/data/dummy_data.dart';
import 'package:gitsync/l10n/app_locale.dart';
import 'package:gitsync/repositories/fake/fake_discord_digest_repo.dart';
import 'package:gitsync/view_models/ask_repo_vm.dart';
import 'package:gitsync/view_models/commits_vm.dart';
import 'package:gitsync/view_models/daily_report_vm.dart';
import 'package:gitsync/view_models/discord_messages_vm.dart';
import 'package:gitsync/view_models/intel_range_vm.dart';
import 'package:gitsync/views/daily/daily_view_page.dart';
import 'package:gitsync/widgets/empty_state.dart';

import '_helpers/locale.dart';

// 06-16: Daily tab empty-state behaviors.
//   #1 whole-range empty  → ONE centered empty state (icon + message + a
//      "Adjust date range" CTA), instead of a column of empty cards.
//   #2 a blank day inside an otherwise-active range → a compact one-line row
//      ("date · No activity") that expands to reveal the Generate action.
//
// In fake mode only TODAY has a report and no day starts with a Discord digest,
// so a past-only range is wholly empty, and a range ending today is mixed
// (today active, prior days blank).

Widget _harness({AppLocale locale = AppLocale.en}) {
  const repoId = DummyData.demoRepoId;
  return pinLocale(
    locale,
    child: MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CommitsViewModel(repoId: repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => DiscordMessagesViewModel(repoId: repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => DailyReportViewModel(repoId: repoId),
          ),
          ChangeNotifierProvider(
            create: (_) => AskRepoViewModel(repoId: repoId),
          ),
          ChangeNotifierProvider(create: (_) => IntelRangeViewModel()),
        ],
        child: const DailyViewPage(repoId: repoId),
      ),
    ),
  );
}

void main() {
  // The fake digest repo is a singleton — reset so a digest seeded in one test
  // doesn't leak into the next and make a "blank" day look active.
  setUp(() => FakeDiscordDigestRepository().reset());
  tearDown(() => FakeDiscordDigestRepository().reset());

  testWidgets('a wholly-empty range shows ONE empty state with an '
      '"Adjust date range" CTA and no day cards', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final intel = tester
        .element(find.byType(DailyViewPage))
        .read<IntelRangeViewModel>();
    final now = DateTime.now();
    // A 3-day range entirely in the past: no reports, no digests → all empty.
    intel.setRange(
      DateTimeRange(
        start: now.subtract(const Duration(days: 4)),
        end: now.subtract(const Duration(days: 2)),
      ),
    );
    await tester.pumpAndSettle();

    // One single empty state, no per-day cards (full or compact).
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No activity in this range'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Adjust date range'),
      findsOneWidget,
    );
    // No compact "No activity" rows and no full report cards.
    expect(find.text('No activity'), findsNothing);
    expect(find.text('Key activity'), findsNothing);

    // Drain the fake Discord backfill timer.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the "Adjust date range" CTA opens the shared range picker',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final intel = tester
        .element(find.byType(DailyViewPage))
        .read<IntelRangeViewModel>();
    final now = DateTime.now();
    intel.setRange(
      DateTimeRange(
        start: now.subtract(const Duration(days: 4)),
        end: now.subtract(const Duration(days: 2)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Adjust date range'));
    await tester.pumpAndSettle();

    // The OS date-range picker dialog is now on screen (shared with the AppBar).
    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    // Close it without picking so we don't leave a dialog open.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a mixed range renders compact rows for blank days and a full '
      'card for the active day', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final report = tester
        .element(find.byType(DailyViewPage))
        .read<DailyReportViewModel>();
    final intel = tester
        .element(find.byType(DailyViewPage))
        .read<IntelRangeViewModel>();
    final now = DateTime.now();
    // 3-day range ending today: today is active (has a report), the two prior
    // days are blank.
    intel.setRange(
      DateTimeRange(start: now.subtract(const Duration(days: 2)), end: now),
    );
    await tester.pumpAndSettle();

    expect(report.rangeDays.length, 3);

    // No whole-range empty state (the range is only partially empty).
    expect(find.byType(EmptyState), findsNothing);

    // The two blank days render as compact "No activity" rows.
    expect(find.text('No activity'), findsNWidgets(2));

    // Today's active card shows the full report body (expanded by default).
    expect(find.text('Key activity'), findsOneWidget);
    expect(
      find.byKey(ValueKey(DailyReportViewModel.dayKeyOf(now))),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a compact blank-day row expands to reveal the Generate action',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final report = tester
        .element(find.byType(DailyViewPage))
        .read<DailyReportViewModel>();
    final intel = tester
        .element(find.byType(DailyViewPage))
        .read<IntelRangeViewModel>();
    final now = DateTime.now();
    intel.setRange(
      DateTimeRange(start: now.subtract(const Duration(days: 2)), end: now),
    );
    await tester.pumpAndSettle();

    final yesterday = now.subtract(const Duration(days: 1));
    final yKey = DailyReportViewModel.dayKeyOf(yesterday);

    // Collapsed: the Generate action is hidden by default.
    expect(find.widgetWithText(FilledButton, 'Generate report'), findsNothing);

    // Tap the compact row for yesterday (its date label) to expand it.
    await tester.tap(find.text(yKey));
    await tester.pumpAndSettle();

    // The existing _DayReportEmpty Generate action is now revealed.
    final generate = find.widgetWithText(FilledButton, 'Generate report');
    expect(generate, findsOneWidget);

    // It still drives per-day generation (report generation is not lost).
    expect(report.isGeneratingDay(yKey), isFalse);
    await tester.tap(generate);
    await tester.pump();
    expect(report.isGeneratingDay(yKey), isTrue);
    await tester.pumpAndSettle();
    expect(report.isGeneratingDay(yKey), isFalse);

    await tester.pump(const Duration(seconds: 1));
  });
}
