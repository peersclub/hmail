/// The app growing past the use-cases it was born with.
///
/// Two defects made the self-extending playbook unable to extend in practice,
/// and these pin both fixes:
///
///  1. **The learner could only see mail the fetcher already asked for.** Every
///     Gmail query was keyword- or sender-constrained, so a school fee circular
///     was never fetched, never "unclaimed", and never learnable. The discovery
///     query is what makes growth possible at all.
///  2. **A learned use-case had nowhere to live.** Anything that was not a bill,
///     delivery, subscription or meeting collapsed into an `AttentionItem` — no
///     amount, no deadline (the email's arrival stood in for one), and the
///     weight and domain of a security alert.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/data/mail/gmail_source.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/sync/sync_engine.dart';
import 'package:hmail/domain/actions.dart';
import 'package:hmail/domain/ignore_list.dart';
import 'package:hmail/domain/insight.dart';
import 'package:hmail/domain/insight_mapper.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/knowledge_mapper.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/scan_settings.dart';

final _now = DateTime(2026, 8, 6, 10);

LearnedItem _item({
  String label = 'School fee demand',
  String typeId = 'greenwood-fee',
  double? amount,
  DateTime? deadline,
  String? url,
  DateTime? lastSeen,
  String sourceEmailId = 'e1',
}) =>
    LearnedItem(
      label: label,
      typeId: typeId,
      summary: 'Term 2 fees are payable',
      amount: amount,
      deadline: deadline,
      url: url,
      lastSeen: lastSeen ?? _now,
      sourceEmailId: sourceEmailId,
    );

void main() {
  group('discovery query', () {
    test('is included by default, and is the last query', () {
      final planned = GmailSource.plannedQueries(const ScanSettings());
      expect(planned.last.label, 'anything new');
      // The whole point: no subject or from constraint, so mail nobody thought
      // to search for still arrives.
      expect(planned.last.query, isNot(contains('subject:')));
      expect(planned.last.query, isNot(contains('from:')));
    });

    test('excludes the categories with no document shape in them', () {
      final query =
          GmailSource.plannedQueries(const ScanSettings()).last.query;
      expect(query, contains('-category:promotions'));
      expect(query, contains('-category:social'));
      expect(query, contains('-category:forums'));
      expect(query, contains('newer_than:'));
    });

    test('can be switched off, and then no query is unconstrained', () {
      final planned =
          GmailSource.plannedQueries(const ScanSettings(scanDiscovery: false));
      expect([for (final p in planned) p.label], isNot(contains('anything new')));
      for (final p in planned) {
        expect(
          p.query.contains('subject:') || p.query.contains('from:') ||
              p.query.contains('filename:'),
          isTrue,
          reason: 'with discovery off every query must be targeted: ${p.query}',
        );
      }
    });

    test('counts toward the scan estimate, so the cost stays honest', () {
      const on = ScanSettings();
      const off = ScanSettings(scanDiscovery: false);
      expect(on.estimatedMaxEmails,
          greaterThan(off.estimatedMaxEmails));
      expect(on.describeScope, contains('anything new'));
    });
  });

  group('LearnedItem', () {
    test('an undated item is never overdue', () {
      expect(_item().isOverdue, isFalse);
    });

    test('a past deadline is overdue', () {
      expect(
        _item(deadline: DateTime.now().subtract(const Duration(days: 1)))
            .isOverdue,
        isTrue,
      );
    });

    test('a dated item survives a week past its date, then goes stale', () {
      final justPast =
          _item(deadline: DateTime.now().subtract(const Duration(days: 3)));
      final longPast =
          _item(deadline: DateTime.now().subtract(const Duration(days: 20)));
      expect(justPast.isStale, isFalse);
      expect(longPast.isStale, isTrue);
    });

    test('an undated item ages out on arrival date instead', () {
      final fresh = _item(lastSeen: DateTime.now());
      final old =
          _item(lastSeen: DateTime.now().subtract(const Duration(days: 40)));
      expect(fresh.isStale, isFalse);
      expect(old.isStale, isTrue);
    });

    test('dedupes per recipe per email, not per recipe', () {
      // Two genuine notices from one recipe must both survive; the same notice
      // re-read must not double up.
      expect(_item(sourceEmailId: 'a').dedupeKey,
          isNot(_item(sourceEmailId: 'b').dedupeKey));
      expect(_item(sourceEmailId: 'a').dedupeKey,
          _item(sourceEmailId: 'a').dedupeKey);
    });

    test('survives a round trip', () {
      final item = _item(
        amount: 42000,
        deadline: DateTime(2026, 8, 15),
        url: 'https://school.example/pay',
      );
      final back = LearnedItem.fromJson(item.toJson());
      expect(back.label, item.label);
      expect(back.typeId, item.typeId);
      expect(back.amount, 42000);
      expect(back.deadline, DateTime(2026, 8, 15));
      expect(back.url, item.url);
    });

    test('a payload from a build without these fields still loads', () {
      final back = LearnedItem.fromJson({
        'label': 'Old card',
        'lastSeen': _now.toIso8601String(),
        'sourceEmailId': 'e1',
      });
      expect(back.typeId, '');
      expect(back.amount, isNull);
      expect(back.deadline, isNull);
    });
  });

  group('mapping a learned type', () {
    ContentType makeType({ProducesKind produces = ProducesKind.generic}) =>
        ContentType(
          id: 'greenwood-fee',
          label: 'School fee demand',
          match: const ContentMatcher(senderDomains: ['greenwood.edu.in']),
          produces: produces,
          fields: const [],
          actions: const [],
          learnedAt: _now,
        );

    EmailMeta makeEmail() => EmailMeta(
          id: 'e1',
          from: 'Accounts <accounts@greenwood.edu.in>',
          subject: 'Term 2 fee payable by 15 August',
          snippet: '',
          body: '',
          date: _now,
        );

    test('generic keeps its amount and its own deadline', () {
      final mapped = mapKnowledge([
        (
          makeEmail(),
          KnowledgeMatch(
            type: makeType(),
            fields: const {'amount': '₹42,000', 'dueDate': '15 Aug 2026'},
            actions: const [],
          ),
        ),
      ]);

      expect(mapped.learned, hasLength(1));
      final item = mapped.learned.single;
      expect(item.label, 'School fee demand');
      expect(item.typeId, 'greenwood-fee');
      expect(item.amount, 42000);
      // The deadline is the date in the document, NOT when the email arrived —
      // the old attention-card path used email.date, which was simply wrong.
      expect(item.deadline, DateTime(2026, 8, 15));
      expect(item.deadline, isNot(_now));
    });

    test('generic with no fields is still a card, just a plainer one', () {
      final mapped = mapKnowledge([
        (
          makeEmail(),
          KnowledgeMatch(type: makeType(), fields: const {}, actions: const []),
        ),
      ]);
      expect(mapped.learned, hasLength(1));
      expect(mapped.learned.single.amount, isNull);
      expect(mapped.learned.single.deadline, isNull);
      // And crucially not an attention item, which is where it used to land.
      expect(mapped.attention, isEmpty);
    });

    test('a typed recipe still maps to its typed insight', () {
      final mapped = mapKnowledge([
        (
          makeEmail(),
          KnowledgeMatch(
            type: makeType(produces: ProducesKind.bill),
            fields: const {'amount': '₹42,000'},
            actions: const [],
          ),
        ),
      ]);
      expect(mapped.bills, hasLength(1));
      expect(mapped.learned, isEmpty);
    });
  });

  group('ranking', () {
    test('a learned card is never a security alert', () {
      // The old path made every unmodellable type an AttentionItem, which the
      // ranker puts in the security domain at weight 100 — so a school
      // circular outranked an overdue bill.
      final insights = snapshotToInsights(
        InsightSnapshot(learned: [_item(amount: 42000)]),
      );
      expect(insights.single.domain, isNot(InsightDomain.security));
      expect(insights.single.weight, lessThan(90));
    });

    test('money puts it in the money domain, nothing puts it in personal', () {
      final withMoney = snapshotToInsights(
        InsightSnapshot(learned: [_item(amount: 500)]),
      ).single;
      final without =
          snapshotToInsights(InsightSnapshot(learned: [_item()])).single;

      expect(withMoney.domain, InsightDomain.money);
      expect(withMoney.trailing, contains('500'));
      expect(without.domain, InsightDomain.personal);
      expect(without.trailing, isNull);
    });

    test('a dated demand for money outranks a bare recognition', () {
      final dated = snapshotToInsights(InsightSnapshot(
        learned: [
          _item(amount: 500, deadline: DateTime.now().add(const Duration(days: 3)))
        ],
      )).single;
      final bare = snapshotToInsights(InsightSnapshot(learned: [_item()])).single;
      expect(dated.weight, greaterThan(bare.weight));
    });

    test('an overdue learned card reads as overdue', () {
      final insight = snapshotToInsights(InsightSnapshot(
        learned: [
          _item(deadline: DateTime.now().subtract(const Duration(days: 2)))
        ],
      )).single;
      expect(insight.overdue, isTrue);
      expect(insight.caption, 'Overdue');
      expect(insight.urgency, UrgencyTier.imminent);
    });

    test('a stale card never reaches the UI', () {
      final insights = snapshotToInsights(InsightSnapshot(
        learned: [
          _item(lastSeen: DateTime.now().subtract(const Duration(days: 60)))
        ],
      ));
      expect(insights, isEmpty);
    });

    test('it offers a correction, like every other family', () {
      final insight =
          snapshotToInsights(InsightSnapshot(learned: [_item()])).single;
      expect(insight.ignoreKind, IgnoreKind.learned);
      expect(insight.correctionSubject, 'School fee demand');
    });
  });

  group('actions', () {
    test('the recipe URL leads, and open-email is always the floor', () {
      final actions =
          actionsForLearned(_item(url: 'https://school.example/pay'));
      expect(actions.first.uri.toString(), 'https://school.example/pay');
      expect(actions.last.kind, ActionKind.openEmail);
    });

    test('a dated card offers a reminder; an overdue one does not', () {
      final upcoming = actionsForLearned(
        _item(deadline: DateTime.now().add(const Duration(days: 5))),
      );
      final past = actionsForLearned(
        _item(deadline: DateTime.now().subtract(const Duration(days: 5))),
      );
      expect(upcoming.any((a) => a.kind == ActionKind.remind), isTrue);
      expect(past.any((a) => a.kind == ActionKind.remind), isFalse);
    });

    test('a card with no URL still opens its email', () {
      final actions = actionsForLearned(_item());
      expect(actions, hasLength(1));
      expect(actions.single.kind, ActionKind.openEmail);
    });

    test('never claims a payment handoff it cannot honour', () {
      // The recipe's confidence does not extend to promising a UPI intent, and
      // the destination hints exist precisely to not mislabel where a tap goes.
      final actions = actionsForLearned(
        _item(amount: 500, url: 'https://school.example/pay'),
      );
      expect(actions.first.kind, ActionKind.openLink);
      expect(actions.first.kind, isNot(ActionKind.pay));
    });
  });

  group('audit and corrections', () {
    test('a rejected email takes its learned card with it', () {
      final audited = applyVerdicts(
        InsightSnapshot(learned: [_item(sourceEmailId: 'bad')]),
        const InsightVerdicts(rejected: {'bad'}),
      );
      expect(audited.learned, isEmpty);
    });

    test('a renamed email renames the card', () {
      final audited = applyVerdicts(
        InsightSnapshot(learned: [_item(sourceEmailId: 'e2')]),
        const InsightVerdicts(renamed: {'e2': 'Greenwood fees'}),
      );
      expect(audited.learned.single.label, 'Greenwood fees');
    });

    test('"not a card" hides every card from that recipe', () {
      final filtered = applyIgnores(
        InsightSnapshot(learned: [_item(), _item(label: 'Policy renewal')]),
        IgnoreList.empty.add(IgnoreRule(
          kind: IgnoreKind.learned,
          subject: 'School fee demand',
          at: _now,
        )),
      );
      expect(filtered.learned, hasLength(1));
      expect(filtered.learned.single.label, 'Policy renewal');
    });
  });

  group('storage', () {
    test('merge keeps both history and fresh cards', () {
      final merged = InsightStore().merge(
        InsightSnapshot(learned: [_item(sourceEmailId: 'old')]),
        InsightSnapshot(learned: [_item(sourceEmailId: 'new')]),
      );
      expect(merged.learned, hasLength(2));
    });

    test('the same card re-read does not double up', () {
      final merged = InsightStore().merge(
        InsightSnapshot(learned: [_item(sourceEmailId: 'same')]),
        InsightSnapshot(learned: [_item(sourceEmailId: 'same')]),
      );
      expect(merged.learned, hasLength(1));
    });

    test('a snapshot round trip keeps them', () {
      final snapshot = InsightSnapshot(learned: [_item(amount: 99)]);
      final back = InsightSnapshot.fromJson(snapshot.toJson());
      expect(back.learned.single.amount, 99);
    });

    test('a snapshot from a build without learned items still loads', () {
      final back = InsightSnapshot.fromJson({'subscriptions': []});
      expect(back.learned, isEmpty);
    });
  });
}
