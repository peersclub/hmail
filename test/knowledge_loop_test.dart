/// The point of the knowledge system, tested end to end: an email shape
/// nobody wrote a rule for is handled correctly on the *second* sync, using
/// only the recipe the app wrote for itself — no model call.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/sync/sync_engine.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/knowledge_mapper.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/data/mail/mail_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A courier nothing in the app knows about.
EmailMeta shipmentEmail() => EmailMeta(
      id: 'ship-1',
      from: 'Porter <no-reply@porter.example>',
      subject: 'Your Porter consignment is on the move',
      snippet: 'Consignment PRT99881234 dispatched',
      body: 'Consignment PRT99881234 has left our hub and is on the move.',
      date: DateTime.now(),
    );

/// The recipe a learner would write for it.
ContentType porterRecipe() => ContentType(
      id: 'porter-consignment',
      label: 'Porter consignment',
      match: const ContentMatcher(
        senderDomains: ['porter.example'],
        subjectAny: ['consignment'],
      ),
      produces: ProducesKind.delivery,
      fields: const [
        FieldRule(
          name: 'trackingNumber',
          pattern: r'Consignment\s+([A-Z]{3}\d{8})',
        ),
      ],
      actions: const [
        ActionTemplate(
          label: 'Track consignment',
          uriTemplate: 'https://porter.example/track/{trackingNumber}',
          kind: 'track',
        ),
      ],
      learnedFromEmailId: 'ship-1',
      learnedAt: DateTime(2026, 8, 2),
      learnedByModel: 'test-model',
    );

class OnlyEmails implements MailSource {
  final List<EmailMeta> emails;
  OnlyEmails(this.emails);
  @override
  Future<List<EmailMeta>> fetchCandidates({
    void Function(String detail)? onProgress,
  }) async =>
      emails;
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an unknown shipment is ignored before the recipe exists', () async {
    final result = await SyncEngine(
      source: OnlyEmails([shipmentEmail()]),
      ai: const NoAi(),
      store: InsightStore(),
    ).runReported();

    expect(result.snapshot.deliveries, isEmpty,
        reason: 'no hand-written rule covers this courier');
    expect(result.report.knowledgeApplied, 0);
  });

  test('with the recipe, the same email becomes a tracked delivery', () async {
    final playbook = Playbook.empty.upsert(porterRecipe());

    final result = await SyncEngine(
      source: OnlyEmails([shipmentEmail()]),
      ai: const NoAi(),
      store: InsightStore(),
    ).runReported(playbook: playbook);

    expect(result.snapshot.deliveries, hasLength(1));
    final delivery = result.snapshot.deliveries.single;
    expect(delivery.merchant, 'Porter consignment');
    expect(delivery.trackingNumber, 'PRT99881234');
    expect(
      delivery.trackingUrl,
      'https://porter.example/track/PRT99881234',
      reason: 'the learned template must carry the real tracking id',
    );
    expect(result.report.knowledgeApplied, 1);
    expect(result.report.unclaimedCount, 0);
  });

  test('a disabled recipe stops applying', () async {
    final playbook =
        Playbook.empty.upsert(porterRecipe()).setEnabled('porter-consignment', false);

    final result = await SyncEngine(
      source: OnlyEmails([shipmentEmail()]),
      ai: const NoAi(),
      store: InsightStore(),
    ).runReported(playbook: playbook);

    expect(result.snapshot.deliveries, isEmpty);
    expect(result.report.knowledgeApplied, 0);
  });

  test('knowledge never displaces a hand-written rule', () async {
    // A greedy recipe that would also claim Amazon shipments.
    final greedy = porterRecipe().copyWith(
      id: 'greedy',
      match: const ContentMatcher(
        senderDomains: ['amazon.in'],
        subjectAny: ['shipped'],
      ),
    );
    final emails = await DemoMailSource().fetchCandidates();

    final result = await SyncEngine(
      source: OnlyEmails(emails),
      ai: const NoAi(),
      store: InsightStore(),
    ).runReported(playbook: Playbook.empty.upsert(greedy));

    final amazon =
        result.snapshot.deliveries.where((d) => d.merchant == 'Amazon');
    expect(amazon, isNotEmpty,
        reason: 'the built-in extractor claims it first, so the recipe '
            'never sees the email');
  });

  group('mapKnowledge', () {
    test('a bill with no parseable amount degrades to an attention card', () {
      final type = porterRecipe().copyWith(
        id: 'odd-bill',
        label: 'Odd bill',
        produces: ProducesKind.bill,
      );
      final email = shipmentEmail();
      final match = Playbook.empty.upsert(type).apply(email);
      expect(match, isNotNull);

      final mapped = mapKnowledge([(email, match!)]);
      expect(mapped.bills, isEmpty);
      expect(mapped.attention, hasLength(1));
      expect(mapped.attention.single.linkUrl, contains('PRT99881234'),
          reason: 'the link is the one thing we must never lose');
    });

    test('an event with no date degrades rather than inventing one', () {
      final type = porterRecipe().copyWith(
        id: 'odd-event',
        produces: ProducesKind.event,
      );
      final email = shipmentEmail();
      final match = Playbook.empty.upsert(type).apply(email)!;

      final mapped = mapKnowledge([(email, match)]);
      expect(mapped.events, isEmpty);
      expect(mapped.attention, hasLength(1));
    });
  });
}
