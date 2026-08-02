/// Proves the backup bundle round-trips through a destination and rehydrates
/// every store — the guarantee a "restore from backup" depends on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/backup/backup_service.dart';
import 'package:hmail/data/backup/backup_target.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/store/knowledge_store.dart';
import 'package:hmail/data/store/settings_store.dart';
import 'package:hmail/data/store/timeline_order_store.dart';
import 'package:hmail/domain/backup_bundle.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackupService serviceForFreshStores() => BackupService(
      insights: InsightStore(),
      knowledge: KnowledgeStore(),
      settings: SettingsStore(),
      timeline: TimelineOrderStore(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('BackupBundle', () {
    test('serializes and deserializes through bytes', () {
      final bundle = BackupBundle(
        createdAt: DateTime(2026, 8, 2, 9, 30),
        deviceLabel: "Victor's iPhone",
        accountEmail: 'v@example.com',
        snapshot: {
          'bills': [
            {'issuer': 'BESCOM'}
          ],
          'deliveries': [
            {'merchant': 'Amazon'},
            {'merchant': 'Myntra'}
          ],
        },
        playbook: {
          'types': [
            {'id': 'gym'},
            {'id': 'school'}
          ]
        },
        settings: {'aiEnabled': true},
        timelineOrder: const ['money', 'commerce'],
      );

      final restored = BackupBundle.fromBytes(bundle.toBytes());

      expect(restored.deviceLabel, "Victor's iPhone");
      expect(restored.accountEmail, 'v@example.com');
      expect(restored.insightCount, 3, reason: '1 bill + 2 deliveries');
      expect(restored.learnedTypeCount, 2);
      expect(restored.timelineOrder, ['money', 'commerce']);
      expect(restored.createdAt, DateTime(2026, 8, 2, 9, 30));
    });

    test('tolerates a legacy/partial document', () {
      final b = BackupBundle.fromJson({'deviceLabel': 'Old phone'});
      expect(b.insightCount, 0);
      expect(b.learnedTypeCount, 0);
      expect(b.timelineOrder, isEmpty);
      expect(b.version, BackupBundle.currentVersion);
    });
  });

  group('collect → restore round-trip', () {
    test('a backup taken on one store set rehydrates a fresh one', () async {
      // Seed device A.
      final aInsights = InsightStore();
      final aKnowledge = KnowledgeStore();
      final aSettings = SettingsStore();
      final aTimeline = TimelineOrderStore();

      await aInsights.save(InsightSnapshot(
        bills: [
          Bill(
            issuer: 'BESCOM',
            amount: 1840,
            currency: '₹',
            sourceEmailId: 'e1',
            lastSeen: DateTime(2026, 8, 1),
          ),
        ],
      ));
      await aKnowledge.save(Playbook(types: [
        ContentType(
          id: 'gym',
          label: 'Gym',
          match: const ContentMatcher(
            senderDomains: ['gym.example'],
            subjectAny: ['membership'],
          ),
          learnedFromEmailId: 'g1',
          learnedAt: DateTime(2026, 8, 1),
        ),
      ]));
      await aSettings.save(const ScanSettings(aiEnabled: false));
      await aTimeline.save(const ['commerce', 'money']);

      final serviceA = BackupService(
        insights: aInsights,
        knowledge: aKnowledge,
        settings: aSettings,
        timeline: aTimeline,
      );
      final target = MemoryBackupTarget();
      final meta = await serviceA.backUpTo(
        target,
        deviceLabel: "Victor's iPhone",
        accountEmail: 'v@example.com',
        now: DateTime(2026, 8, 2),
      );
      expect(meta.createdAt, DateTime(2026, 8, 2));
      expect(meta.sizeBytes, greaterThan(0));

      // Wipe to simulate a fresh install, then restore from the same target.
      SharedPreferences.setMockInitialValues({});
      final serviceB = serviceForFreshStores();
      final outcome = await serviceB.restoreFrom(target);

      expect(outcome, isNotNull);
      expect(outcome!.insightCount, 1);
      expect(outcome.learnedTypeCount, 1);
      expect(outcome.settingsRestored, isTrue);

      // The stores really hold the restored data.
      final snap = await serviceB.insights.load();
      expect(snap!.bills.single.issuer, 'BESCOM');
      final pb = await serviceB.knowledge.load();
      expect(pb.types.single.id, 'gym');
      final scan = await serviceB.settings.load();
      expect(scan.aiEnabled, isFalse);
      final order = await serviceB.timeline.load();
      expect(order, ['commerce', 'money']);
    });

    test('restoring from an empty destination is a no-op that reports null',
        () async {
      final service = serviceForFreshStores();
      final outcome = await service.restoreFrom(MemoryBackupTarget());
      expect(outcome, isNull);
    });

    test('an unavailable destination surfaces a BackupException', () async {
      final service = serviceForFreshStores();
      expect(
        () => service.backUpTo(MemoryBackupTarget(available: false),
            deviceLabel: 'x'),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
