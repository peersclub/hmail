/// Integration coverage for the wiring between insights and actions.
///
/// The unit tests prove `actionsForX()` returns the right links; these prove
/// the screens actually surface them — that a tap on a bill row opens a sheet
/// with a working Pay button rather than doing nothing.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/app/nomail_app.dart';
import 'package:hmail/domain/backfill_stats.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/glass/glass.dart';
import 'package:hmail/ui/screens/money_screen.dart';
import 'package:hmail/ui/screens/onboarding_screen.dart';
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

  /// Money has more sections than a phone-sized test surface can build, and a
  /// ListView only builds what's near the viewport — so a row further down
  /// simply isn't in the tree to be found. A tall surface builds everything
  /// and keeps these tests about actions rather than scroll mechanics.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

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

  /// A row inside one named section. Netflix appears twice on Money — once as
  /// a subscription, once as a price change — so a bare text finder is
  /// ambiguous and the section is what disambiguates it.
  Finder rowInSection(String section, String title) => find.descendant(
        of: find.ancestor(
          of: find.text(section.toUpperCase()),
          matching: find.byType(GlassSection),
        ),
        matching: find.widgetWithText(GlassRow, title),
      );

  group('demo pipeline surfaces actionable insights', () {
    testWidgets('bill row opens an action sheet with a pay option',
        (tester) async {
      useTallSurface(tester);
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
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const MoneyScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      await tapRow(tester, rowInSection('Subscriptions', 'Netflix'));

      expect(find.text('Manage plan'), findsOneWidget);
    });

    testWidgets('a price hike surfaces on Money and offers a plan review',
        (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const MoneyScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      // Demo history carries Netflix at ₹599 against the fixture's ₹649, so
      // the real detector — not a canned fixture — produced this row.
      final change = controller.snapshot.activePriceChanges.single;
      expect(change.service, 'Netflix');
      expect(change.monthlyDelta, 50);

      expect(find.text('PRICE CHANGES'), findsOneWidget);
      await tapRow(tester, rowInSection('Price changes', 'Netflix'));

      // A rise leads with "Review plan"; the plain subscription row says
      // "Manage plan". Different framing for a different question.
      expect(find.text('Review plan'), findsOneWidget);
    });

    testWidgets('the hero reports what the price watch caught', (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const MoneyScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1 price change caught'),
        findsOneWidget,
      );
    });

    testWidgets('demo meeting invite appears on Today with a join action',
        (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump();
      // Past ShellScreen's delay, then settled so the modal is fully pushed —
      // a half-pushed modal is worse than either state here, because the guard
      // below would not find its button and would leave it covering Today.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // First-scan modal covers Today — dismiss it before tapping a row.
      if (find.text('Show my Today').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('Show my Today'));
        await tester.tap(find.text('Show my Today'));
        await tester.pumpAndSettle();
      }

      final events = controller.snapshot.todayEvents;
      expect(events, isNotEmpty,
          reason: 'demo fixtures include a Google Meet invite for today');
      expect(events.first.meetingUrl, contains('meet.google.com'));

      await tapRow(tester, find.text(events.first.title));

      expect(find.text('Join on Meet'), findsOneWidget);
      expect(find.text('Open calendar'), findsOneWidget);
    });

    testWidgets('first sync raises the money-shot modal, dismiss hides it',
        (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      expect(controller.showMoneyShot, isTrue,
          reason: 'an empty-to-populated sync is a first scan');

      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump();
      // ShellScreen waits out a timer before pushing the modal, so the clock
      // has to be advanced explicitly: a pending timer schedules no frame, so
      // pumpAndSettle alone would return without ever firing it. Settling
      // afterwards is what lets the pushed route finish animating in — firing
      // the timer only gets the push started.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('HIDING IN YOUR INBOX'), findsOneWidget);
      expect(find.text('Show my Today'), findsOneWidget);

      await tester.ensureVisible(find.text('Show my Today'));
      await tester.tap(find.text('Show my Today'));
      await tester.pumpAndSettle();
      expect(controller.showMoneyShot, isFalse);
      expect(find.text('HIDING IN YOUR INBOX'), findsNothing);
    });

    testWidgets('reduced-motion money-shot shows the final figure immediately',
        (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await controller.enterDemo();
      final stats = controller.backfillStats;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              disableAnimations: true,
            ),
            child: const CupertinoApp(home: ShellScreen()),
          ),
        ),
      );
      await tester.pump();
      // The push is behind a timer regardless of the animation setting, so the
      // clock still has to clear it; disableAnimations only makes the count-up
      // land on its final figure once the modal is up.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.textContaining(stats.annualRecurringDisplay.replaceAll('/yr', '')),
          findsWidgets);
    });
  });

  group('first-run onboarding carousel', () {
    testWidgets('cold signed-out boot shows page 1; Skip lands on SignIn',
        (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const NoMailApp(),
        ),
      );
      await controller.init();
      await tester.pumpAndSettle();

      expect(find.text('NoMail'), findsWidgets);
      expect(find.textContaining('minus the inbox'), findsOneWidget);
      expect(controller.seenOnboarding, isFalse);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(controller.seenOnboarding, isTrue);
      expect(find.text('Welcome to NoMail'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('seen_onboarding skips the carousel', (tester) async {
      SharedPreferences.setMockInitialValues({'seen_onboarding': true});
      final controller = AppController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const NoMailApp(),
        ),
      );
      await controller.init();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Welcome to NoMail'), findsOneWidget);
    });

    testWidgets('last page offers Google and sample auth', (tester) async {
      useTallSurface(tester);
      final controller = AppController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const NoMailApp(),
        ),
      );
      await controller.init();
      await tester.pumpAndSettle();

      // Jump to last page — avoids intermediate layout under auth chrome.
      final pageView = tester.widget<PageView>(find.byType(PageView));
      pageView.controller!.jumpToPage(2);
      await tester.pumpAndSettle();

      expect(find.textContaining('One tap'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Explore with Sample Data'), findsOneWidget);
    });

    testWidgets('Replay intro returns to the carousel after Skip',
        (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues({'seen_onboarding': true});
      final controller = AppController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const NoMailApp(),
        ),
      );
      await controller.init();
      await tester.pumpAndSettle();

      expect(find.text('Welcome to NoMail'), findsOneWidget);

      await tester.tap(find.text('Replay intro'));
      await tester.pumpAndSettle();

      expect(controller.seenOnboarding, isFalse);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.textContaining('minus the inbox'), findsOneWidget);
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
