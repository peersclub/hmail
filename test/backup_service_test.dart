/// Proves the backup bundle round-trips through a destination and rehydrates
/// every store — the guarantee a "restore from backup" depends on.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/backup/backup_service.dart';
import 'package:hmail/data/backup/backup_target.dart';
import 'package:hmail/data/backup/drive_backup_target.dart';
import 'package:hmail/data/mail/gmail_auth.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/store/knowledge_store.dart';
import 'package:hmail/data/store/settings_store.dart';
import 'package:hmail/data/store/timeline_order_store.dart';
import 'package:hmail/domain/backup_bundle.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:hmail/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackupService serviceForFreshStores() => BackupService(
      insights: InsightStore(),
      knowledge: KnowledgeStore(),
      settings: SettingsStore(),
      timeline: TimelineOrderStore(),
    );

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
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

  group('Drive failure messages name the cause and the recovery', () {
    DriveBackupTarget targetWithIssue(DriveAuthIssue issue) =>
        DriveBackupTarget(
          signedIn: () async => true,
          connect: ({bool interactive = false}) async =>
              (api: null, issue: issue),
        );

    Future<String> uploadError(DriveAuthIssue issue) async {
      try {
        await targetWithIssue(issue).upload(BackupBundle(
          createdAt: DateTime(2026, 8, 2),
          deviceLabel: 'x',
        ));
        fail('expected a BackupException');
      } on BackupException catch (e) {
        return e.message;
      }
    }

    test('declined consent tells the user what to allow', () async {
      final msg = await uploadError(DriveAuthIssue.declined);
      expect(msg, contains('declined'));
      expect(msg, contains('Allow'), reason: 'must offer the recovery');
    });

    test('not signed in points at connecting an account', () async {
      final msg = await uploadError(DriveAuthIssue.notSignedIn);
      expect(msg.toLowerCase(), contains('google account'));
    });

    test('plumbing failure points at the connection', () async {
      final msg = await uploadError(DriveAuthIssue.failed);
      expect(msg.toLowerCase(), contains('connection'));
    });

    test('silent metadata check never throws on an ungranted scope', () async {
      final t = targetWithIssue(DriveAuthIssue.notGranted);
      expect(await t.latest(), isNull);
      expect(await t.isAuthorized(), isFalse);
    });
  });

  group('AppController backup journey states', () {
    test('backUpNow surfaces an in-flow notice and stamps prefs', () async {
      final target = MemoryBackupTarget();
      final app = AppController(backupTargets: {'gdrive': target});

      final ok = await app.backUpNow();

      expect(ok, isTrue);
      expect(app.backupError, isNull);
      expect(app.backupNotice, contains('Backed up'));
      expect(app.backupNoticeScope, BackupErrorScope.backup);
      expect(app.backupPrefs.lastBackupAt, isNotNull);
      expect(app.remoteBackupMeta, isNotNull);
      expect(app.backupActivity, BackupActivity.idle);
    });

    test('backup failure lands scoped under the backup action', () async {
      final app = AppController(
        backupTargets: {'gdrive': MemoryBackupTarget(available: false)},
      );

      final ok = await app.backUpNow();

      expect(ok, isFalse);
      expect(app.backupError, isNotNull);
      expect(app.backupErrorScope, BackupErrorScope.backup);
      expect(app.backupNotice, isNull);
      expect(app.backupPrefs.lastBackupAt, isNull,
          reason: 'a failed backup must not claim success');
    });

    test('restore is staged: prepare holds a candidate, confirm applies it',
        () async {
      // Seed a backup from one "device"…
      final target = MemoryBackupTarget();
      final appA = AppController(backupTargets: {'gdrive': target});
      await appA.backUpNow();

      // …then restore on a "fresh install".
      SharedPreferences.setMockInitialValues({});
      final appB = AppController(backupTargets: {'gdrive': target});

      final meta = await appB.prepareRestore();
      expect(meta, isNotNull);
      expect(appB.restoreCandidate, isNotNull,
          reason: 'nothing is applied before the user confirms');

      final outcome = await appB.confirmRestore();
      expect(outcome, isNotNull);
      expect(appB.restoreCandidate, isNull);
      expect(appB.backupNotice, contains('Restored'));
      expect(appB.backupNoticeScope, BackupErrorScope.restore);
    });

    test('restore from an empty destination errors under the restore action',
        () async {
      final app = AppController(
        backupTargets: {'gdrive': MemoryBackupTarget()},
      );

      final meta = await app.prepareRestore();

      expect(meta, isNull);
      expect(app.backupError, contains('No backup found'));
      expect(app.backupErrorScope, BackupErrorScope.restore);
    });

    test('cancelRestore drops the candidate without applying', () async {
      final target = MemoryBackupTarget();
      final appA = AppController(backupTargets: {'gdrive': target});
      await appA.backUpNow();

      final appB = AppController(backupTargets: {'gdrive': target});
      await appB.prepareRestore();
      appB.cancelRestore();

      expect(appB.restoreCandidate, isNull);
      expect(await appB.confirmRestore(), isNull,
          reason: 'confirm after cancel must be a no-op');
    });
  });
}
