/// Proves the Settings controls actually reach the pipeline: scan scope
/// changes the Gmail queries, the AI switch is honoured, and every sync
/// produces a report the Processing screen can show.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/data/mail/gmail_source.dart';
import 'package:hmail/data/mail/mail_source.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/sync/sync_engine.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:hmail/domain/sync_report.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/screens/processing_screen.dart';
import 'package:hmail/ui/screens/scan_screen.dart';
import 'package:hmail/ui/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records that analyze() ran, and can hand back canned verdicts.
class SpyAi implements InsightAi {
  final InsightVerdicts verdicts;
  int calls = 0;

  SpyAi({this.verdicts = InsightVerdicts.empty});

  @override
  bool get isConfigured => true;

  @override
  String get label => 'spy';

  @override
  Future<AiResult> analyze({
    required InsightSnapshot extracted,
    required List<EmailMeta> unclaimed,
    List<EmailMeta> sources = const [],
  }) async {
    calls++;
    return AiResult(verdicts: verdicts);
  }
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('scan scope drives the Gmail queries', () {
    test('all domains on produces seven queries', () {
      final queries = GmailSource.queriesFor(const ScanSettings());
      expect(queries, hasLength(7),
          reason: 'money(2)+deliveries+events+reads+travel');
    });

    test('turning a domain off removes its query', () {
      final queries = GmailSource.queriesFor(
        const ScanSettings(
            scanDeliveries: false,
            scanEvents: false,
            scanReads: false,
            scanTravel: false,
        scanDiscovery: false),
      );
      expect(queries, hasLength(2), reason: 'money is receipts + bills');
      expect(queries.any((q) => q.contains('shipped')), isFalse);
      expect(queries.any((q) => q.contains('invitation')), isFalse);
    });

    test('history depth reaches the receipts query', () {
      final queries =
          GmailSource.queriesFor(const ScanSettings(historyDays: 730));
      expect(queries.first, contains('newer_than:730d'));
    });

    test('short history tightens, but never widens, the other windows', () {
      final short = GmailSource.queriesFor(
        const ScanSettings(historyDays: 90),
      );
      // Deliveries cap at 30d and must not stretch to 90d.
      expect(short.any((q) => q.contains('shipped') && q.contains('30d')),
          isTrue);

      final long = GmailSource.queriesFor(
        const ScanSettings(historyDays: 730),
      );
      expect(long.any((q) => q.contains('shipped') && q.contains('30d')),
          isTrue);
    });

    test('nothing selected means no queries at all', () {
      final queries = GmailSource.queriesFor(const ScanSettings(
        scanMoney: false,
        scanDeliveries: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
        scanDiscovery: false,
      ));
      expect(queries, isEmpty);
    });
  });

  group('runReported', () {
    SyncEngine engine(InsightAi ai) => SyncEngine(
          source: DemoMailSource(),
          ai: ai,
          store: InsightStore(),
        );

    test('reports what was read and found', () async {
      final result = await engine(const NoAi()).runReported();
      final report = result.report;

      expect(report.emailsFetched, greaterThan(5));
      expect(report.totalInsights, greaterThan(0));
      expect(report.stage, SyncStage.done);
      expect(report.duration, greaterThan(Duration.zero));
      expect(report.headline, contains('emails'));
    });

    test('AI off skips the model entirely but still briefs', () async {
      final ai = SpyAi();
      final result = await engine(ai).runReported(
        settings: const ScanSettings(aiEnabled: false),
      );

      expect(ai.calls, 0, reason: 'the switch must actually gate the call');
      expect(result.report.aiRan, isFalse);
      expect(result.snapshot.brief, isNotNull,
          reason: 'the rule brief always exists');
    });

    test('AI on runs the audit and records its corrections', () async {
      final firstPass = await engine(const NoAi()).runReported();
      final target = firstPass.snapshot.deliveries.first;

      final ai = SpyAi(
        verdicts: InsightVerdicts(rejected: {target.sourceEmailId}),
      );
      final result = await engine(ai).runReported();

      expect(ai.calls, 1);
      expect(result.report.aiRan, isTrue);
      expect(result.report.aiRejected, 1);
      expect(result.report.aiNotes, isNotEmpty);
      expect(
        result.snapshot.deliveries
            .any((d) => d.sourceEmailId == target.sourceEmailId),
        isFalse,
        reason: 'a rejected insight must not survive into the snapshot',
      );
    });

    test('runReported carries travel, payments and returns through', () async {
      // Guards a regression where the reported build dropped these lists while
      // the plain run() path kept them — the demo fixtures have all three.
      final result = await engine(const NoAi()).runReported();
      final snap = result.snapshot;
      expect(snap.travel, isNotEmpty, reason: 'demo IndiGo flight');
      expect(snap.payments, isNotEmpty, reason: 'demo failed payment + refund');
      expect(snap.returns, isNotEmpty, reason: 'demo Myntra return + warranty');
    });

    test('stages are emitted in pipeline order', () async {
      final seen = <SyncStage>[];
      await engine(const NoAi()).runReported(onStage: seen.add);

      expect(seen.first, SyncStage.fetching);
      expect(seen.last, SyncStage.done);
      expect(seen, contains(SyncStage.extracting));
    });
  });

  group('settings screens render', () {
    Widget wrap(AppController controller, Widget child) =>
        ChangeNotifierProvider.value(
          value: controller,
          child: CupertinoApp(home: child),
        );

    testWidgets('Settings hub shows every section', (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Scanning'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Daily Brief'), findsOneWidget);
      expect(find.text('Knowledge'), findsOneWidget);
      // Sits below the fold in the lazy list once Knowledge is present.
      await tester.scrollUntilVisible(find.text('Export Insights'), 200);
      expect(find.text('Export Insights'), findsOneWidget);
      // The scan scope is described in place, not hidden behind the tap.
      expect(find.textContaining('up to 175 emails'), findsOneWidget);
    });

    testWidgets('Scan screen shows the estimate and toggles', (tester) async {
      final controller = AppController();
      await tester.pumpWidget(wrap(controller, const ScanScreen()));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('100'), findsWidgets);
      expect(find.text('emails per scan, at most'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Packages'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);
    });

    testWidgets('turning off a domain updates the estimate live',
        (tester) async {
      final controller = AppController();
      await tester.pumpWidget(wrap(controller, const ScanScreen()));
      await tester.pump(const Duration(milliseconds: 600));

      final meetings = find.byType(CupertinoSwitch).last;
      await tester.ensureVisible(meetings);
      await tester.pumpAndSettle();
      await tester.tap(meetings); // Meetings off
      await tester.pumpAndSettle();

      expect(controller.settings.scanEvents, isFalse);
      // The hero card scrolls out of the lazy list when we reach the switch,
      // so assert the recomputed value rather than the rendered glyph (the
      // previous test already proves the estimate renders).
      expect(controller.settings.estimatedMaxEmails, 150,
          reason: 'money(2) + deliveries + reads + travel + discovery, '
              'x 25 per query');
    });

    testWidgets('Processing screen lists the pipeline and audit',
        (tester) async {
      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(wrap(controller, const ProcessingScreen()));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('PIPELINE'), findsOneWidget,
          reason: 'SectionLabel uppercases what it renders');
      expect(find.text('AI AUDIT'), findsOneWidget);
      expect(find.text('Reading mail'), findsOneWidget);
    });
  });
}
