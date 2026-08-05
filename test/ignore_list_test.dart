import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/backup/backup_service.dart';
import 'package:hmail/data/store/ignore_store.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/store/knowledge_store.dart';
import 'package:hmail/data/store/settings_store.dart';
import 'package:hmail/data/store/timeline_order_store.dart';
import 'package:hmail/domain/backup_bundle.dart';
import 'package:hmail/domain/ignore_list.dart';
import 'package:hmail/domain/insight_mapper.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:hmail/ui/glass/glass.dart';
import 'package:hmail/ui/screens/money_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 8, 5, 10);

IgnoreRule _rule(IgnoreKind kind, String subject) =>
    IgnoreRule(kind: kind, subject: subject, at: _now);

InsightSnapshot _snapshot() => InsightSnapshot(
      subscriptions: [
        Subscription(
          service: 'Netflix',
          amount: 649,
          currency: 'INR',
          cadence: Cadence.monthly,
          lastSeen: _now,
          sourceEmailId: 's1',
        ),
      ],
      bills: [
        Bill(
          issuer: 'BESCOM',
          amount: 1840,
          currency: 'INR',
          dueDate: _now.add(const Duration(days: 5)),
          lastSeen: _now,
          sourceEmailId: 'b1',
        ),
      ],
      deliveries: [
        Delivery(
          merchant: 'GitHub',
          carrier: null,
          status: DeliveryStatus.shipped,
          lastSeen: _now,
          sourceEmailId: 'd1',
        ),
      ],
      priceChanges: [
        PriceChange(
          service: 'Netflix',
          oldAmount: 599,
          newAmount: 649,
          currency: 'INR',
          cadence: Cadence.monthly,
          detectedAt: _now,
          sourceEmailId: 's1',
        ),
      ],
    );

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('IgnoreRule', () {
    test('normalises the subject so matching is case- and space-proof', () {
      final rule = _rule(IgnoreKind.delivery, '  GitHub  ');
      expect(rule.subject, 'github');
      expect(rule.key, 'delivery|github');
    });

    test('reads back as a sentence', () {
      expect(_rule(IgnoreKind.delivery, 'GitHub').label, 'Packages from github');
      expect(_rule(IgnoreKind.bill, 'Substack').label, 'Bills from substack');
    });

    test('survives a round trip', () {
      final rule = _rule(IgnoreKind.bill, 'Substack');
      final back = IgnoreRule.fromJson(rule.toJson());
      expect(back, rule);
      expect(back!.at, rule.at);
    });

    test('an entry this build cannot read is skipped, not fatal', () {
      expect(IgnoreRule.fromJson({'kind': 'teleportation'}), isNull);
      expect(IgnoreRule.fromJson({'kind': 'bill', 'subject': '  '}), isNull);

      // …and the surrounding list survives it.
      final list = IgnoreList.fromJson({
        'rules': [
          {'kind': 'nonsense', 'subject': 'x'},
          _rule(IgnoreKind.bill, 'Substack').toJson(),
        ],
      });
      expect(list.length, 1);
    });
  });

  group('IgnoreList', () {
    test('adding the same correction twice is a no-op', () {
      final list = IgnoreList.empty
          .add(_rule(IgnoreKind.delivery, 'GitHub'))
          .add(_rule(IgnoreKind.delivery, 'github'));
      expect(list.length, 1);
    });

    test('kind is part of the identity', () {
      final list = IgnoreList.empty
          .add(_rule(IgnoreKind.delivery, 'Amazon'))
          .add(_rule(IgnoreKind.bill, 'Amazon'));
      expect(list.length, 2);
      expect(list.hides(IgnoreKind.delivery, 'Amazon'), isTrue);
      expect(list.hides(IgnoreKind.subscription, 'Amazon'), isFalse);
    });

    test('matching is exact, never a substring', () {
      // Otherwise "Amazon" would silence "Amazon Pay", which is a different
      // service with different money attached.
      final list = IgnoreList.empty.add(_rule(IgnoreKind.payment, 'Amazon'));
      expect(list.hides(IgnoreKind.payment, 'Amazon Pay'), isFalse);
    });

    test('removing restores', () {
      final rule = _rule(IgnoreKind.delivery, 'GitHub');
      final list = IgnoreList.empty.add(rule);
      expect(list.remove(rule.key).isEmpty, isTrue);
    });
  });

  group('applyIgnores', () {
    test('with no rules the snapshot passes through untouched', () {
      final snapshot = _snapshot();
      expect(identical(applyIgnores(snapshot, IgnoreList.empty), snapshot),
          isTrue);
    });

    test('hides only the corrected family', () {
      final filtered = applyIgnores(
        _snapshot(),
        IgnoreList.empty.add(_rule(IgnoreKind.delivery, 'GitHub')),
      );
      expect(filtered.deliveries, isEmpty);
      expect(filtered.bills, hasLength(1));
      expect(filtered.subscriptions, hasLength(1));
    });

    test('correcting a subscription takes its price change with it', () {
      final filtered = applyIgnores(
        _snapshot(),
        IgnoreList.empty.add(_rule(IgnoreKind.subscription, 'Netflix')),
      );
      expect(filtered.subscriptions, isEmpty);
      expect(filtered.priceChanges, isEmpty);
    });

    test('correcting a bill leaves the subscription of the same name', () {
      final snapshot = _snapshot();
      final filtered = applyIgnores(
        snapshot,
        IgnoreList.empty.add(_rule(IgnoreKind.bill, 'Netflix')),
      );
      expect(filtered.subscriptions, hasLength(1));
      expect(filtered.bills, hasLength(1)); // BESCOM, not Netflix
    });

    test('a hidden insight never reaches the mapper', () {
      final filtered = applyIgnores(
        _snapshot(),
        IgnoreList.empty.add(_rule(IgnoreKind.delivery, 'GitHub')),
      );
      final ids = [for (final i in snapshotToInsights(filtered)) i.id];
      expect(ids.any((id) => id.startsWith('delivery:')), isFalse);
    });
  });

  group('mapper corrections', () {
    test('every insight family offers one', () {
      // A family with no correction is a dead end for the user, so this is
      // asserted across the board rather than per type.
      final insights = snapshotToInsights(_snapshot());
      expect(insights, isNotEmpty);
      for (final insight in insights) {
        expect(insight.ignoreKind, isNotNull, reason: insight.id);
        expect(insight.correctionSubject, isNotNull, reason: insight.id);
      }
    });

    test('a nameless subject yields no correction', () {
      // Nothing to generalise on means the button would hide one email and
      // then silently stop working — better absent.
      final insights = snapshotToInsights(InsightSnapshot(
        attention: [
          AttentionItem(
            title: '   ',
            reason: 'unclear',
            date: _now,
            sourceEmailId: 'a1',
          ),
        ],
      ));
      expect(insights.single.correctionSubject, isNull);
    });

    test('a meeting keys on the organiser, not the title', () {
      final insights = snapshotToInsights(InsightSnapshot(
        events: [
          EventItem(
            title: 'Weekly standup',
            start: _now.add(const Duration(days: 1)),
            organizer: 'standup-bot@corp.com',
            lastSeen: _now,
            sourceEmailId: 'e1',
          ),
        ],
      ));
      expect(insights.single.correctionSubject, 'standup-bot@corp.com');
    });
  });

  group('IgnoreStore', () {
    test('round trips through preferences', () async {
      final store = IgnoreStore();
      await store.save(IgnoreList.empty.add(_rule(IgnoreKind.bill, 'Substack')));
      final loaded = await store.load();
      expect(loaded.hides(IgnoreKind.bill, 'Substack'), isTrue);
    });

    test('garbage in preferences reads as no corrections', () async {
      SharedPreferences.setMockInitialValues({'ignore_rules_v1': 'not json'});
      expect((await IgnoreStore().load()).isEmpty, isTrue);
    });
  });

  group('backup', () {
    test('corrections ride along and come back', () async {
      final service = BackupService(
        insights: InsightStore(),
        knowledge: KnowledgeStore(),
        settings: SettingsStore(),
        timeline: TimelineOrderStore(),
      );
      await IgnoreStore()
          .save(IgnoreList.empty.add(_rule(IgnoreKind.delivery, 'GitHub')));

      final bundle = await service.collect(deviceLabel: 'Test');
      expect(bundle.ignores, isNotNull);

      // Fresh device: nothing stored, then the bundle lands.
      SharedPreferences.setMockInitialValues({});
      expect((await IgnoreStore().load()).isEmpty, isTrue);
      await service.restore(bundle);

      expect(
        (await IgnoreStore().load()).hides(IgnoreKind.delivery, 'GitHub'),
        isTrue,
      );
    });

    test('a bundle written before corrections existed restores fine', () async {
      final service = BackupService(
        insights: InsightStore(),
        knowledge: KnowledgeStore(),
        settings: SettingsStore(),
        timeline: TimelineOrderStore(),
      );
      final old = BackupBundle.fromJson({
        'version': 1,
        'createdAt': _now.toIso8601String(),
        'deviceLabel': 'Old iPhone',
      });
      expect(old.ignores, isNull);
      await service.restore(old);
      expect((await IgnoreStore().load()).isEmpty, isTrue);
    });
  });

  group('controller', () {
    test('a correction hides insights but keeps them for the undo', () async {
      final controller = AppController();
      await controller.enterDemo();
      final before = controller.snapshot.subscriptions.length;
      expect(before, greaterThan(0));

      final service = controller.snapshot.subscriptions.first.service;
      await controller.ignoreInsight(IgnoreKind.subscription, service);

      expect(controller.snapshot.subscriptions, hasLength(before - 1));
      expect(controller.ignores.length, 1);

      await controller.unignore(controller.ignores.rules.single.key);
      expect(controller.snapshot.subscriptions, hasLength(before));
    });

    test('an empty subject is refused rather than stored', () async {
      final controller = AppController();
      await controller.ignoreInsight(IgnoreKind.bill, '   ');
      expect(controller.ignores.isEmpty, isTrue);
    });

    test('corrections survive a rescan', () async {
      // The point of a rule: the next scan must not undo the user's decision.
      final controller = AppController();
      await controller.enterDemo();
      await controller.ignoreInsight(IgnoreKind.subscription, 'Netflix');
      await controller.sync();

      expect(
        controller.snapshot.subscriptions.any((s) => s.service == 'Netflix'),
        isFalse,
      );
    });
  });

  group('Money screen', () {
    testWidgets('offers the correction and applies it', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = AppController();
      await controller.enterDemo();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: const CupertinoApp(home: MoneyScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 900));

      final row = find.descendant(
        of: find.ancestor(
          of: find.text('SUBSCRIPTIONS'),
          matching: find.byType(GlassSection),
        ),
        matching: find.widgetWithText(GlassRow, 'Netflix'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not a subscription'));
      await tester.pumpAndSettle();

      expect(controller.ignores.hides(IgnoreKind.subscription, 'Netflix'),
          isTrue);
      expect(
        controller.snapshot.subscriptions.any((s) => s.service == 'Netflix'),
        isFalse,
      );
    });
  });
}
