/// Integration coverage for the wiring between insights and actions.
///
/// The unit tests prove `actionsForX()` returns the right links; these prove
/// the screens actually surface them — that a tap on a bill row opens a sheet
/// with a working Pay button rather than doing nothing.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/domain/backfill_stats.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/glass/glass.dart';
import 'package:hmail/ui/screens/money_screen.dart';
import 'package:hmail/ui/screens/shell_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(AppController controller, Widget child) =>
      ChangeNotifierProvider.value(
        value: controller,
        child: CupertinoApp(home: child),
      );

  /// Rows live far down a scroll view; a raw tap() would miss the hit target.
  Future<void> tapRow(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    // The sheet now waits (briefly) on the installed-app sweep, so pump past
    // that timeout before settling.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('demo pipeline surfaces actionable insights', () {
    testWidgets('bill row opens an action sheet with a pay option',
        (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const MoneyScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      // BESCOM's demo fixture carries a upi:// link.
      await tapRow(tester, find.text('BESCOM'));

      expect(find.text('Pay via UPI'), findsOneWidget);
      expect(find.text('Open email'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('subscription row offers its manage page', (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const MoneyScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      // Target the row, not the share-bar legend that shares the label.
      await tapRow(tester, find.widgetWithText(GlassRow, 'Netflix'));

      expect(find.text('Manage plan'), findsOneWidget);
    });

    testWidgets('demo meeting invite appears on Today with a join action',
        (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      final events = controller.snapshot.todayEvents;
      expect(events, isNotEmpty,
          reason: 'demo fixtures include a Google Meet invite for today');
      expect(events.first.meetingUrl, contains('meet.google.com'));

      await tapRow(tester, find.text(events.first.title));

      expect(find.text('Join on Meet'), findsOneWidget);
      expect(find.text('Open calendar'), findsOneWidget);
    });

    testWidgets('first sync raises the money-shot card, dismiss hides it',
        (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      expect(controller.showMoneyShot, isTrue,
          reason: 'an empty-to-populated sync is a first scan');

      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Hiding in your inbox'), findsOneWidget);

      controller.dismissMoneyShot();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hiding in your inbox'), findsNothing);
    });
  });

  group('BackfillStats over the demo pipeline', () {
    test('reports what the first scan found', () async {
      final controller = AppController();
      await controller.enterDemo();
      final stats = BackfillStats.fromSnapshot(controller.snapshot);

      expect(stats.subscriptionCount, greaterThan(0));
      expect(stats.headline, contains('subscription'));
      expect(stats.annualRecurringDisplay, startsWith('₹'));
    });
  });
}
