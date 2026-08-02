import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/data/mail/mail_source.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/sync/sync_engine.dart';
import 'package:hmail/domain/brief_builder.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/screens/shell_screen.dart';
import 'package:hmail/ui/screens/sign_in_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: '');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(AppController controller, Widget child) =>
      ChangeNotifierProvider.value(
        value: controller,
        child: CupertinoApp(home: child),
      );

  group('SyncEngine (demo pipeline end-to-end)', () {
    test('demo emails produce insights across every domain', () async {
      final engine = SyncEngine(
        source: DemoMailSource(),
        ai: const NoAi(),
        store: InsightStore(),
      );
      final snapshot = await engine.run();

      expect(snapshot.subscriptions, isNotEmpty);
      expect(snapshot.bills, isNotEmpty);
      expect(snapshot.deliveries, isNotEmpty);
      expect(snapshot.attention, isNotEmpty,
          reason: 'heuristic attention should catch the security alert');
      expect(snapshot.brief, isNotNull,
          reason: 'rule brief must exist without any AI key');
      expect(snapshot.brief!.headline, isNotEmpty);
      expect(snapshot.emailsScanned, greaterThan(5));
    });
  });

  group('buildRuleBrief', () {
    test('leads with the most urgent fact', () {
      final snapshot = InsightSnapshot(bills: [
        Bill(
          issuer: 'BESCOM',
          amount: 1840,
          currency: 'INR',
          dueDate: DateTime.now().add(const Duration(days: 2)),
          lastSeen: DateTime.now(),
          sourceEmailId: 'x',
        ),
      ]);
      final brief = buildRuleBrief(snapshot);
      expect(brief.headline, contains('BESCOM'));
      expect(brief.bullets, isNotEmpty);
    });

    test('produces a calm headline when nothing is urgent', () {
      final brief = buildRuleBrief(const InsightSnapshot());
      expect(brief.headline, contains('quiet'));
    });
  });

  group('InsightStore', () {
    test('merge keeps most recent version by dedupe key', () {
      final store = InsightStore();
      final old = InsightSnapshot(subscriptions: [
        Subscription(
          service: 'Netflix',
          amount: 499,
          currency: 'INR',
          cadence: Cadence.monthly,
          lastSeen: DateTime(2026, 6, 1),
          sourceEmailId: 'old',
        ),
      ]);
      final fresh = InsightSnapshot(subscriptions: [
        Subscription(
          service: 'Netflix',
          amount: 649,
          currency: 'INR',
          cadence: Cadence.monthly,
          lastSeen: DateTime(2026, 8, 1),
          sourceEmailId: 'new',
        ),
      ]);
      final merged = store.merge(old, fresh);
      expect(merged.subscriptions, hasLength(1));
      expect(merged.subscriptions.single.amount, 649);
    });
  });

  group('UI', () {
    testWidgets('sign-in screen offers Google and demo paths', (tester) async {
      await tester.pumpWidget(wrap(AppController(), const SignInScreen()));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Welcome to NoMail'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Explore with Sample Data'), findsOneWidget);
    });

    testWidgets('demo mode renders brief and demo banner', (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ShellScreen()));
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.textContaining('Demo data'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Daily brief'), findsOneWidget);
    });
  });
}
