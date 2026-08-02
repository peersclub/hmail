import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/sync_report.dart';

// Fixed clock — nothing here may depend on DateTime.now().
final startedAt = DateTime(2030, 6, 15, 10);

SyncReport report({
  int emailsFetched = 84,
  int subscriptionsFound = 8,
  int billsFound = 4,
  int deliveriesFound = 5,
  int eventsFound = 2,
  int unclaimedCount = 0,
  bool aiRan = true,
  int aiRejected = 1,
  int aiRenamed = 2,
  List<String> aiNotes = const [],
  String? aiError,
  SyncStage stage = SyncStage.done,
}) => SyncReport(
  startedAt: startedAt,
  duration: const Duration(seconds: 12),
  emailsFetched: emailsFetched,
  subscriptionsFound: subscriptionsFound,
  billsFound: billsFound,
  deliveriesFound: deliveriesFound,
  eventsFound: eventsFound,
  unclaimedCount: unclaimedCount,
  aiRan: aiRan,
  aiRejected: aiRejected,
  aiRenamed: aiRenamed,
  aiNotes: aiNotes,
  aiError: aiError,
  stage: stage,
);

Delivery delivery(String merchant, String sourceEmailId) => Delivery(
  merchant: merchant,
  status: DeliveryStatus.shipped,
  lastSeen: startedAt,
  sourceEmailId: sourceEmailId,
);

void main() {
  group('headline', () {
    test('rich case names emails, insights and AI corrections', () {
      expect(
        report().headline,
        'Read 84 emails, found 19 insights, AI corrected 3.',
      );
    });

    test('drops the AI clause when the AI did not run', () {
      expect(
        report(aiRan: false, aiRejected: 0, aiRenamed: 0).headline,
        'Read 84 emails, found 19 insights.',
      );
    });

    test('drops the AI clause when the AI changed nothing', () {
      expect(
        report(aiRejected: 0, aiRenamed: 0).headline,
        'Read 84 emails, found 19 insights.',
      );
    });

    test('says nothing new when the scan found no insights', () {
      expect(
        report(
          subscriptionsFound: 0,
          billsFound: 0,
          deliveriesFound: 0,
          eventsFound: 0,
        ).headline,
        'Read 84 emails, nothing new.',
      );
    });

    test('surfaces an AI error instead of a correction count', () {
      expect(
        report(aiError: 'rate limited').headline,
        'Read 84 emails, found 19 insights — AI check failed.',
      );
    });

    test('singularises one email and one insight', () {
      expect(
        report(
          emailsFetched: 1,
          subscriptionsFound: 1,
          billsFound: 0,
          deliveriesFound: 0,
          eventsFound: 0,
          aiRejected: 0,
          aiRenamed: 0,
        ).headline,
        'Read 1 email, found 1 insight.',
      );
    });

    test('empty report reads as never scanned', () {
      final empty = SyncReport.empty();
      expect(empty.neverSynced, isTrue);
      expect(empty.stage, SyncStage.idle);
      expect(empty.headline, 'No scan yet.');
      expect(empty.breakdown, isEmpty);
    });

    test('failed stage reports the failure', () {
      expect(
        report(stage: SyncStage.failed, aiError: 'no network').headline,
        'Scan failed — no network.',
      );
    });
  });

  group('breakdown', () {
    test('lists every non-zero category in pipeline order', () {
      expect(report().breakdown, [
        '8 subscriptions',
        '4 bills',
        '5 packages',
        '2 meetings',
      ]);
    });

    test('omits zero categories entirely and singularises', () {
      expect(
        report(subscriptionsFound: 0, billsFound: 1, eventsFound: 0).breakdown,
        ['1 bill', '5 packages'],
      );
    });
  });

  group('counts', () {
    test('totalInsights sums the four extraction categories only', () {
      expect(report(unclaimedCount: 40).totalInsights, 19);
    });

    test('aiRejectRate is rejected over total insights', () {
      expect(report(aiRejected: 19).aiRejectRate, 1.0);
      expect(report(aiRejected: 0).aiRejectRate, 0.0);
      expect(
        report(
          subscriptionsFound: 6,
          billsFound: 4,
          deliveriesFound: 0,
          eventsFound: 0,
          aiRejected: 5,
        ).aiRejectRate,
        0.5,
      );
    });

    test('aiRejectRate is 0 rather than NaN when there are no insights', () {
      final none = report(
        subscriptionsFound: 0,
        billsFound: 0,
        deliveriesFound: 0,
        eventsFound: 0,
        aiRejected: 3,
      );
      expect(none.totalInsights, 0);
      expect(none.aiRejectRate, 0.0);
      expect(none.aiRejectRate.isNaN, isFalse);
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      final original = report(
        unclaimedCount: 12,
        aiNotes: const ['Dropped Github — not a real package'],
        aiError: 'timeout',
        stage: SyncStage.done,
      );
      final restored = SyncReport.fromJson(original.toJson());

      expect(restored.startedAt, original.startedAt);
      expect(restored.duration, original.duration);
      expect(restored.emailsFetched, 84);
      expect(restored.subscriptionsFound, 8);
      expect(restored.billsFound, 4);
      expect(restored.deliveriesFound, 5);
      expect(restored.eventsFound, 2);
      expect(restored.unclaimedCount, 12);
      expect(restored.aiRan, isTrue);
      expect(restored.aiRejected, 1);
      expect(restored.aiRenamed, 2);
      expect(restored.aiNotes, original.aiNotes);
      expect(restored.aiError, 'timeout');
      expect(restored.stage, SyncStage.done);
      expect(restored.headline, original.headline);
    });

    test('fromJson tolerates an empty map', () {
      final blank = SyncReport.fromJson(const {});
      expect(blank.emailsFetched, 0);
      expect(blank.totalInsights, 0);
      expect(blank.aiRan, isFalse);
      expect(blank.aiNotes, isEmpty);
      expect(blank.aiError, isNull);
      expect(blank.stage, SyncStage.idle);
      expect(blank.duration, Duration.zero);
      expect(blank.neverSynced, isTrue);
    });
  });

  group('copyWith', () {
    test('replaces only the named fields', () {
      final updated = report().copyWith(
        emailsFetched: 3,
        stage: SyncStage.saving,
      );
      expect(updated.emailsFetched, 3);
      expect(updated.stage, SyncStage.saving);
      expect(updated.subscriptionsFound, 8);
      expect(updated.aiRenamed, 2);
      expect(updated.startedAt, startedAt);
    });

    test('clearAiError erases a previous failure', () {
      final failed = report(aiError: 'timeout');
      expect(failed.copyWith().aiError, 'timeout');
      expect(failed.copyWith(clearAiError: true).aiError, isNull);
    });

    test('withAudit folds an audit summary in and clears a stale error', () {
      final folded = report(aiRan: false, aiError: 'timeout').withAudit(
        const AiAuditSummary(rejected: 2, renamed: 1, notes: ['a', 'b', 'c']),
      );
      expect(folded.aiRan, isTrue);
      expect(folded.aiRejected, 2);
      expect(folded.aiRenamed, 1);
      expect(folded.aiNotes, ['a', 'b', 'c']);
      expect(folded.aiError, isNull);
      expect(folded.aiCorrections, 3);
    });
  });

  group('stage labels', () {
    test('every stage has user-facing text', () {
      expect(SyncStage.idle.label, 'Not scanned yet');
      expect(SyncStage.fetching.label, 'Reading mail');
      expect(SyncStage.extracting.label, 'Finding insights');
      expect(SyncStage.auditing.label, 'AI checking results');
      expect(SyncStage.saving.label, 'Saving');
      expect(SyncStage.done.label, 'Up to date');
      expect(SyncStage.failed.label, 'Failed');
      for (final stage in SyncStage.values) {
        expect(stage.label, isNotEmpty);
      }
    });

    test('isBusy covers exactly the in-flight stages', () {
      expect(SyncStage.values.where((s) => s.isBusy).toList(), [
        SyncStage.fetching,
        SyncStage.extracting,
        SyncStage.auditing,
        SyncStage.learning,
        SyncStage.saving,
      ]);
    });
  });

  group('AiAuditSummary.fromVerdicts', () {
    final snapshot = InsightSnapshot(
      deliveries: [delivery('Github', 'gh-1'), delivery('Nct', 'fk-1')],
    );
    const verdicts = InsightVerdicts(
      rejected: {'gh-1'},
      renamed: {'fk-1': 'Flipkart'},
    );

    test('names the thing affected, never the raw email id', () {
      final audit = AiAuditSummary.fromVerdicts(verdicts, preAudit: snapshot);

      expect(audit.rejected, 1);
      expect(audit.renamed, 1);
      expect(audit.notes.length, 2);
      expect(audit.notes.first, contains('Github'));
      expect(audit.notes.first, startsWith('Dropped'));
      expect(audit.notes.last, contains('Nct'));
      expect(audit.notes.last, contains('Flipkart'));
      for (final note in audit.notes) {
        expect(note, isNot(contains('gh-1')));
        expect(note, isNot(contains('fk-1')));
      }
    });

    test('a rejected id matching nothing produces no note', () {
      final audit = AiAuditSummary.fromVerdicts(
        const InsightVerdicts(rejected: {'ghost-9'}),
        preAudit: snapshot,
      );
      expect(audit.notes, isEmpty);
      expect(audit.rejected, 0);
      expect(audit.isEmpty, isTrue);
    });

    test('a rename to the existing name is not a change', () {
      final audit = AiAuditSummary.fromVerdicts(
        const InsightVerdicts(renamed: {'gh-1': 'Github'}),
        preAudit: snapshot,
      );
      expect(audit.notes, isEmpty);
      expect(audit.renamed, 0);
    });

    test('rejection wins over a rename for the same insight', () {
      final audit = AiAuditSummary.fromVerdicts(
        const InsightVerdicts(
          rejected: {'fk-1'},
          renamed: {'fk-1': 'Flipkart'},
        ),
        preAudit: snapshot,
      );
      expect(audit.notes, ['Dropped Nct — not a real package']);
      expect(audit.renamed, 0);
    });

    test('empty verdicts short-circuit to the empty summary', () {
      expect(
        AiAuditSummary.fromVerdicts(InsightVerdicts.empty, preAudit: snapshot),
        same(AiAuditSummary.empty),
      );
    });

    test('describes each insight kind by its own noun', () {
      final mixed = InsightSnapshot(
        subscriptions: [
          Subscription(
            service: 'Netflix',
            amount: 199,
            currency: 'INR',
            cadence: Cadence.monthly,
            lastSeen: startedAt,
            sourceEmailId: 's-1',
          ),
        ],
        bills: [
          Bill(
            issuer: 'Airtel',
            amount: 500,
            currency: 'INR',
            lastSeen: startedAt,
            sourceEmailId: 'b-1',
          ),
        ],
        events: [
          EventItem(
            title: 'Standup',
            start: startedAt,
            lastSeen: startedAt,
            sourceEmailId: 'e-1',
          ),
        ],
      );
      final audit = AiAuditSummary.fromVerdicts(
        const InsightVerdicts(rejected: {'s-1', 'b-1', 'e-1'}),
        preAudit: mixed,
      );
      expect(audit.notes, [
        'Dropped Netflix — not a real subscription',
        'Dropped Airtel — not a real bill',
        'Dropped Standup — not a real meeting',
      ]);
    });
  });
}
