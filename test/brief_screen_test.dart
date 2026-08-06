/// The daily summary has to be reachable and complete.
///
/// The card on Today caps its headline at four lines and ellipsises, so a long
/// brief was partly unreadable with nowhere to go for the rest. These pin that
/// the card opens the full thing and that the full thing truncates nothing.
library;

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/mail/gmail_auth.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/screens/brief_screen.dart';
import 'package:hmail/ui/screens/today_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Long on purpose: the truncation this screen exists to escape only shows up
/// on a headline the card cannot fit.
const _longHeadline =
    'Two bills need paying this week and a package arrives today, while your '
    'Netflix plan renews on Thursday at the new price and the Myntra return '
    'window closes tomorrow evening, which is the one that cannot wait';

/// `AppController.init()` awaits a Google Sign-In plugin that stalls under a
/// test binding — see the layout matrix for the same stub.
class _NoSession extends GmailAuth {
  @override
  Future<bool> resumeSilently() async => false;
}

InsightSnapshot _withBrief() => InsightSnapshot(
      bills: [
        Bill(
          issuer: 'BESCOM',
          amount: 1840,
          currency: 'INR',
          dueDate: DateTime.now().add(const Duration(days: 2)),
          lastSeen: DateTime.now(),
          sourceEmailId: 'b1',
        ),
      ],
      brief: DailyBrief(
        headline: _longHeadline,
        bullets: const [
          'BESCOM ₹1,840 due Tuesday',
          'Myntra: send it back or keep it',
          'Netflix renews Thursday at ₹699',
        ],
        generatedAt: DateTime.now(),
      ),
      lastSyncedAt: DateTime.now(),
      emailsScanned: 212,
    );

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));

  Widget wrap(AppController controller, Widget child) =>
      ChangeNotifierProvider.value(
        value: controller,
        child: CupertinoApp(home: child),
      );

  /// Boots with [snapshot] already stored, so the screen renders real loaded
  /// state rather than something poked in from the test.
  Future<AppController> boot(
    WidgetTester tester,
    Widget screen, {
    InsightSnapshot? snapshot,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (snapshot != null)
        'insight_snapshot_v11': jsonEncode(snapshot.toJson()),
    });

    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = AppController(auth: _NoSession());
    await controller.init();
    await tester.pumpWidget(wrap(controller, screen));
    await tester.pumpAndSettle();
    return controller;
  }

  group('the brief card opens the full brief', () {
    testWidgets('the card is tappable and pushes the brief screen',
        (tester) async {
      // Booting with a stored snapshot rather than entering demo: a first-data
      // sync raises the money-shot modal, whose barrier swallows the tap. The
      // gesture is what is under test, not the modal.
      await boot(tester, const TodayScreen(), snapshot: _withBrief());

      // The affordance has to be visible, or the tap is a secret.
      expect(find.text('Read it all'), findsOneWidget);

      await tester.tap(find.text('Read it all'));
      await tester.pumpAndSettle();

      expect(find.byType(BriefScreen), findsOneWidget);
    });
  });

  group('the full brief truncates nothing', () {
    testWidgets('the headline is rendered without a line cap', (tester) async {
      // A brief the card could not have fitted.
      await boot(tester, const BriefScreen(), snapshot: _withBrief());

      final headline = tester.widget<Text>(find.text(_longHeadline));
      expect(headline.maxLines, isNull,
          reason: 'this screen exists because the card caps at four lines');
      expect(headline.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('every bullet is shown', (tester) async {
      await boot(tester, const BriefScreen(), snapshot: _withBrief());

      expect(find.textContaining('BESCOM ₹1,840'), findsOneWidget);
      expect(find.textContaining('send it back or keep it'), findsOneWidget);
      expect(find.textContaining('Netflix renews'), findsOneWidget);
    });

    testWidgets('it names who wrote it', (tester) async {
      await boot(tester, const BriefScreen(), snapshot: _withBrief());

      // No sync has run here, so no model wrote this — the screen must not
      // claim one did. A rule-built summary and an AI judgement are different
      // things to be holding.
      expect(find.text('Written by rules'), findsOneWidget);
      expect(find.text('Written by AI'), findsNothing);
    });

    testWidgets('it says how much mail it was drawn from', (tester) async {
      await boot(tester, const BriefScreen(), snapshot: _withBrief());

      expect(find.textContaining('212 emails read'), findsOneWidget);
    });
  });

  group('with no brief', () {
    testWidgets('it explains rather than showing a blank screen',
        (tester) async {
      await boot(tester, const BriefScreen());

      expect(find.text('No Brief Yet'), findsOneWidget);
    });
  });

  group('Today still shows the glance', () {
    testWidgets('the card keeps its four-line cap', (tester) async {
      await boot(tester, const TodayScreen(), snapshot: _withBrief());

      final headline = tester.widget<Text>(find.text(_longHeadline));
      expect(headline.maxLines, 4);
    });
  });
}
