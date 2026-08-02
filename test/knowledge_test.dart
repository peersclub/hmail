import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/knowledge_store.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 8, 1, 9);

EmailMeta email({
  String id = 'm1',
  String from = 'noreply@example.com',
  String subject = '',
  String snippet = '',
  String body = '',
  DateTime? date,
}) =>
    EmailMeta(
      id: id,
      from: from,
      subject: subject,
      snippet: snippet,
      body: body,
      date: date ?? _now,
    );

ContentType type({
  String id = 'test-type',
  String label = 'Test type',
  ContentMatcher? match,
  ProducesKind produces = ProducesKind.generic,
  List<FieldRule> fields = const [],
  List<ActionTemplate> actions = const [],
  bool enabled = true,
}) =>
    ContentType(
      id: id,
      label: label,
      match: match ?? const ContentMatcher(senderDomains: ['example.com']),
      produces: produces,
      fields: fields,
      actions: actions,
      learnedFromEmailId: 'seed-1',
      learnedAt: _now,
      learnedByModel: 'claude-haiku-4.5',
      enabled: enabled,
    );

/// The canonical fixture: an IRCTC e-ticket, the exact shape the hardcoded
/// extractors miss today.
final irctcEmail = email(
  id: 'irctc-1',
  from: 'ticketadmin@irctc.co.in',
  subject: 'Booking Confirmed on IRCTC, Train: 12951, PNR 4512345678',
  snippet: 'Your e-ticket for MUMBAI CENTRAL to NEW DELHI is confirmed.',
  body: 'Dear Customer,\n'
      'Transaction ID 100003456789\n'
      'PNR 4512345678\n'
      'Train No/Name 12951 / MMCT NDLS RAJDHANI\n'
      'Date of Journey 12-Aug-2026, Class 3A, Coach B4, Seat 21\n',
);

final irctcType = ContentType(
  id: 'irctc-eticket',
  label: 'IRCTC e-ticket',
  match: const ContentMatcher(
    senderDomains: ['irctc.co.in'],
    subjectAny: ['booking confirmed', 'e-ticket'],
    bodyAll: ['pnr'],
  ),
  produces: ProducesKind.event,
  fields: const [
    FieldRule(name: 'pnr', pattern: r'PNR\s*:?\s*(\d{10})'),
    FieldRule(name: 'trainNumber', pattern: r'Train\s*No[/\w\s]*?(\d{5})'),
  ],
  actions: const [
    ActionTemplate(
      label: 'Check PNR status',
      uriTemplate: 'https://www.irctc.co.in/online-charts/pnr/{pnr}',
      kind: 'track',
    ),
  ],
  learnedFromEmailId: 'irctc-1',
  learnedAt: _now,
  learnedByModel: 'claude-haiku-4.5',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ContentMatcher', () {
    test('sender domains are any-of, substring-tested', () {
      const matcher = ContentMatcher(senderDomains: ['irctc', 'railyatri']);
      expect(matcher.matches(email(from: 'ticketadmin@irctc.co.in')), isTrue);
      expect(matcher.matches(email(from: 'hi@railyatri.in')), isTrue);
      expect(matcher.matches(email(from: 'billing@bescom.co.in')), isFalse);
    });

    test('subject terms are any-of, case-insensitive', () {
      const matcher = ContentMatcher(subjectAny: ['e-ticket', 'boarding pass']);
      expect(matcher.matches(email(subject: 'Your E-Ticket is ready')), isTrue);
      expect(matcher.matches(email(subject: 'BOARDING PASS · 6E203')), isTrue);
      expect(matcher.matches(email(subject: 'Weekly digest')), isFalse);
    });

    test('body terms are all-of', () {
      const matcher = ContentMatcher(
        senderDomains: ['irctc'],
        bodyAll: ['pnr', 'coach'],
      );
      expect(
        matcher.matches(email(from: 'a@irctc.co.in', body: 'PNR 1 Coach B4')),
        isTrue,
      );
      // Only one of the two required terms present.
      expect(
        matcher.matches(email(from: 'a@irctc.co.in', body: 'PNR 1 only')),
        isFalse,
      );
    });

    test('sender and subject constraints must both hold when both are set', () {
      const matcher = ContentMatcher(
        senderDomains: ['irctc'],
        subjectAny: ['booking confirmed'],
      );
      expect(
        matcher.matches(
            email(from: 'a@irctc.co.in', subject: 'Booking Confirmed')),
        isTrue,
      );
      expect(
        matcher.matches(email(from: 'a@irctc.co.in', subject: 'Newsletter')),
        isFalse,
      );
    });

    test('a matcher with no sender and no subject matches nothing', () {
      const wide = ContentMatcher();
      expect(wide.isAnchored, isFalse);
      expect(wide.matches(irctcEmail), isFalse);
      expect(wide.matches(email(subject: 'anything', body: 'anything')),
          isFalse);
    });

    test('body-only matcher cannot swallow the inbox either', () {
      const bodyOnly = ContentMatcher(bodyAll: ['the']);
      expect(bodyOnly.isAnchored, isFalse);
      expect(bodyOnly.matches(email(body: 'the quick brown fox')), isFalse);
    });

    test('specificity grows with more and longer constraints', () {
      const loose = ContentMatcher(senderDomains: ['irctc.co.in']);
      const tight = ContentMatcher(
        senderDomains: ['irctc.co.in'],
        subjectAny: ['booking confirmed'],
        bodyAll: ['pnr'],
      );
      expect(tight.specificity, greaterThan(loose.specificity));
      expect(const ContentMatcher().specificity, 0);
    });
  });

  group('FieldRule', () {
    test('extracts the single capture group', () {
      const rule = FieldRule(name: 'pnr', pattern: r'PNR\s*(\d{10})');
      expect(rule.extract(irctcEmail), '4512345678');
    });

    test('nearKeyword windows the search past earlier decoys', () {
      final shipment = email(
        body: 'Order ID 1111111111 placed on 1 Aug.\n'
            'Tracking number 9999999999 with Blue Dart.',
      );
      const windowed = FieldRule(
        name: 'tracking',
        pattern: r'\b(\d{10})\b',
        nearKeyword: 'tracking number',
      );
      const unwindowed = FieldRule(name: 'tracking', pattern: r'\b(\d{10})\b');

      expect(windowed.extract(shipment), '9999999999');
      // Without the window the order ID wins purely by position — this is the
      // false match the windowing exists to prevent.
      expect(unwindowed.extract(shipment), '1111111111');
    });

    test('nearKeyword absent from the email yields null', () {
      const rule = FieldRule(
        name: 'tracking',
        pattern: r'\b(\d{10})\b',
        nearKeyword: 'awb number',
      );
      expect(rule.extract(email(body: 'Tracking 1234567890')), isNull);
    });

    test('a value beyond the ~120 char window is not found', () {
      final filler = 'x' * 200;
      final message = email(body: 'Tracking number:$filler 9999999999');
      const rule = FieldRule(
        name: 'tracking',
        pattern: r'\b(\d{10})\b',
        nearKeyword: 'tracking number',
      );
      expect(rule.extract(message), isNull);
    });

    test('an invalid regex returns null instead of throwing', () {
      const bad = FieldRule(name: 'oops', pattern: r'([unclosed');
      expect(bad.isWellFormed, isFalse);
      expect(() => bad.extract(irctcEmail), returnsNormally);
      expect(bad.extract(irctcEmail), isNull);
    });

    test('no match returns null', () {
      const rule = FieldRule(name: 'pnr', pattern: r'PNR\s*(\d{10})');
      expect(rule.extract(email(body: 'nothing here')), isNull);
    });

    test('matching is case-insensitive and searches original-case text', () {
      const rule = FieldRule(name: 'code', pattern: r'ref\s+([A-Z0-9]{6})');
      expect(rule.extract(email(body: 'REF AB12CD')), 'AB12CD');
    });
  });

  group('ActionTemplate', () {
    test('substitutes placeholders', () {
      const action = ActionTemplate(
        label: 'Check PNR status',
        uriTemplate: 'https://www.irctc.co.in/online-charts/pnr/{pnr}',
        kind: 'track',
      );
      expect(action.placeholders, ['pnr']);
      expect(
        action.build({'pnr': '4512345678'}).toString(),
        'https://www.irctc.co.in/online-charts/pnr/4512345678',
      );
    });

    test('URL-encodes substituted values', () {
      const action = ActionTemplate(
        label: 'Track',
        uriTemplate: 'https://track.example.com/?id={ref}',
      );
      final uri = action.build({'ref': 'A B&C'});
      expect(uri, isNotNull);
      expect(uri.toString(), contains('%26'));
      expect(uri.toString(), isNot(contains(' ')));
    });

    test('returns null when a referenced field is missing or blank', () {
      const action = ActionTemplate(
        label: 'Track',
        uriTemplate: 'https://track.example.com/{trackingNumber}',
      );
      expect(action.build(const {}), isNull);
      expect(action.build(const {'trackingNumber': '   '}), isNull);
      // Never emit a URL carrying a literal placeholder.
      expect(action.build(const {'other': 'x'}), isNull);
    });

    test('rejects a template with no scheme and a blocked scheme', () {
      const noScheme =
          ActionTemplate(label: 'Go', uriTemplate: 'track.example.com/{ref}');
      const blocked =
          ActionTemplate(label: 'Go', uriTemplate: 'javascript:alert({ref})');
      expect(noScheme.build(const {'ref': '1'}), isNull);
      expect(blocked.build(const {'ref': '1'}), isNull);
    });

    test('non-http schemes an Indian inbox needs are allowed', () {
      const upi = ActionTemplate(
        label: 'Pay',
        uriTemplate: 'upi://pay?pa={vpa}&am={amount}',
        kind: 'pay',
      );
      expect(upi.build(const {'vpa': 'a@okhdfc', 'amount': '499'}), isNotNull);
    });
  });

  group('Playbook.apply', () {
    test('IRCTC e-ticket end to end', () {
      const playbook = Playbook(types: []);
      final book = playbook.upsert(irctcType);
      final hit = book.apply(irctcEmail);

      expect(hit, isNotNull);
      expect(hit!.type.id, 'irctc-eticket');
      expect(hit.fields['pnr'], '4512345678');
      expect(hit.fields['trainNumber'], '12951');
      expect(hit.actions, hasLength(1));
      expect(hit.actions.single.kind, 'track');
      expect(hit.actions.single.uri.toString(), contains('4512345678'));
      expect(hit.title, 'IRCTC e-ticket');
      expect(hit.subtitle, 'Pnr: 4512345678');
    });

    test('returns null when nothing matches', () {
      final book = const Playbook().upsert(irctcType);
      expect(book.apply(email(from: 'x@zomato.com', subject: 'Order')), isNull);
    });

    test('disabled entries are skipped', () {
      final book = const Playbook().upsert(irctcType.copyWith(enabled: false));
      expect(book.apply(irctcEmail), isNull);
      // ...but the shape still counts as taught, so the AI does not relearn it.
      expect(book.knows(irctcEmail), isTrue);
    });

    test('the more specific of two matching entries wins', () {
      final loose = type(
        id: 'irctc-any',
        label: 'IRCTC mail',
        match: const ContentMatcher(senderDomains: ['irctc']),
      );
      final book = const Playbook().upsert(loose).upsert(irctcType);
      expect(book.candidatesFor(irctcEmail), hasLength(2));
      expect(book.apply(irctcEmail)!.type.id, 'irctc-eticket');

      // Insertion order must not change the outcome.
      final reversed = const Playbook().upsert(irctcType).upsert(loose);
      expect(reversed.apply(irctcEmail)!.type.id, 'irctc-eticket');
    });

    test('actions whose fields are missing are dropped, not rendered broken',
        () {
      final partial = irctcType.copyWith(
        actions: const [
          ActionTemplate(
            label: 'Check PNR status',
            uriTemplate: 'https://www.irctc.co.in/pnr/{pnr}',
            kind: 'track',
          ),
          ActionTemplate(
            label: 'Download ticket',
            uriTemplate: 'https://www.irctc.co.in/ticket/{transactionId}',
            kind: 'openLink',
          ),
        ],
      );
      final hit = const Playbook().upsert(partial).apply(irctcEmail)!;
      expect(hit.actions.map((a) => a.label), ['Check PNR status']);
      expect(
        hit.actions.every((a) => !a.uri.toString().contains('{')),
        isTrue,
      );
    });

    test('a broken field rule degrades to a missing field, not a crash', () {
      final broken = irctcType.copyWith(
        fields: const [
          FieldRule(name: 'pnr', pattern: r'([unclosed'),
          FieldRule(name: 'trainNumber', pattern: r'Train\s*No[/\w\s]*?(\d{5})'),
        ],
      );
      final hit = const Playbook().upsert(broken).apply(irctcEmail)!;
      expect(hit.fields.containsKey('pnr'), isFalse);
      expect(hit.fields['trainNumber'], '12951');
      expect(hit.actions, isEmpty);
      expect(hit.subtitle, 'Train number: 12951');
    });

    test('subtitle is null when nothing was extracted', () {
      final fieldless = irctcType.copyWith(fields: const [], actions: const []);
      expect(const Playbook().upsert(fieldless).apply(irctcEmail)!.subtitle,
          isNull);
    });

    test('applyAll partitions matched from unclaimed', () {
      final book = const Playbook().upsert(irctcType);
      final other = email(id: 'other', from: 'x@swiggy.in', subject: 'Order');
      final result = book.applyAll([irctcEmail, other]);

      expect(result.matched, hasLength(1));
      expect(result.matched.single.fields['pnr'], '4512345678');
      expect(result.unclaimed.map((e) => e.id), ['other']);
    });

    test('an empty playbook claims nothing', () {
      final result = const Playbook().applyAll([irctcEmail]);
      expect(result.matched, isEmpty);
      expect(result.unclaimed, hasLength(1));
      expect(const Playbook().knows(irctcEmail), isFalse);
    });
  });

  group('Playbook mutation', () {
    test('upsert replaces by id rather than duplicating', () {
      final book = const Playbook()
          .upsert(irctcType)
          .upsert(irctcType.copyWith(label: 'IRCTC ticket (v2)'));
      expect(book.types, hasLength(1));
      expect(book.byId('irctc-eticket')!.label, 'IRCTC ticket (v2)');
    });

    test('upsert appends a new id and leaves the original instance alone', () {
      const original = Playbook();
      final book = original.upsert(irctcType).upsert(type(id: 'other'));
      expect(book.types.map((t) => t.id), ['irctc-eticket', 'other']);
      expect(original.types, isEmpty);
    });

    test('remove drops by id and is a no-op for unknown ids', () {
      final book = const Playbook().upsert(irctcType).upsert(type(id: 'other'));
      expect(book.remove('irctc-eticket').types.map((t) => t.id), ['other']);
      expect(book.remove('nope').types, hasLength(2));
    });

    test('setEnabled flips one entry without touching the rest', () {
      final book = const Playbook().upsert(irctcType).upsert(type(id: 'other'));
      final off = book.setEnabled('irctc-eticket', false);
      expect(off.byId('irctc-eticket')!.enabled, isFalse);
      expect(off.byId('other')!.enabled, isTrue);
    });
  });

  group('ContentType.validate', () {
    test('a well-formed entry has no problems', () {
      expect(irctcType.validate(), isEmpty);
      expect(irctcType.isValid, isTrue);
    });

    test('catches an empty id and a non-slug id', () {
      expect(irctcType.copyWith(id: '').validate(),
          contains(matches(RegExp('id is empty'))));
      expect(irctcType.copyWith(id: 'IRCTC Ticket').validate(),
          contains(matches(RegExp('not a lowercase slug'))));
    });

    test('catches an empty label', () {
      expect(irctcType.copyWith(label: '  ').validate(),
          contains(matches(RegExp('label is empty'))));
    });

    test('catches an over-broad matcher and too-short terms', () {
      final wide =
          irctcType.copyWith(match: const ContentMatcher(bodyAll: ['pnr']));
      expect(wide.validate(), contains(matches(RegExp('over-broad'))));

      final short = irctcType
          .copyWith(match: const ContentMatcher(senderDomains: ['in']));
      expect(short.validate(), contains(matches(RegExp('too short'))));
    });

    test('catches a malformed template and unknown placeholders', () {
      final bad = irctcType.copyWith(actions: const [
        ActionTemplate(label: 'Go', uriTemplate: 'irctc.co.in/pnr/{pnr}'),
        ActionTemplate(
            label: 'Refund', uriTemplate: 'https://x.example.com/{refundId}'),
      ]);
      final problems = bad.validate();
      expect(problems, contains(matches(RegExp('malformed uriTemplate'))));
      expect(problems, contains(matches(RegExp('unknown field'))));
    });

    test('catches bad regexes and wrong capture-group counts', () {
      final bad = irctcType.copyWith(fields: const [
        FieldRule(name: 'a', pattern: r'([unclosed'),
        FieldRule(name: 'b', pattern: r'(\d+)-(\d+)'),
        FieldRule(name: 'c', pattern: r'\d+'),
      ]);
      final problems = bad.validate();
      expect(problems, contains(matches(RegExp('invalid regex'))));
      expect(
        problems.where((p) => p.contains('exactly one capture group')),
        hasLength(2),
      );
    });

    test('counts named groups but not lookarounds as captures', () {
      final ok = irctcType.copyWith(fields: const [
        FieldRule(name: 'pnr', pattern: r'(?<=PNR\s)(?:no\s)?(?<code>\d{10})'),
        FieldRule(name: 'amt', pattern: r'(?:Rs\.?|₹)\s?([\d,]+)(?!\d)'),
      ]);
      expect(ok.validate().where((p) => p.contains('capture group')), isEmpty);
      expect(ok.fields.first.isWellFormed, isTrue);
      expect(ok.fields.first.extract(irctcEmail), '4512345678');
    });

    test('catches duplicate and empty field names', () {
      final bad = irctcType.copyWith(fields: const [
        FieldRule(name: 'pnr', pattern: r'(\d{10})'),
        FieldRule(name: 'pnr', pattern: r'(\d{10})'),
        FieldRule(name: '', pattern: r'(\d{10})'),
      ]);
      final problems = bad.validate();
      expect(problems, contains(matches(RegExp('duplicate field name'))));
      expect(problems, contains(matches(RegExp('empty name'))));
    });

    test('caps fields and actions, and the engine honours the cap', () {
      final greedy = irctcType.copyWith(
        fields: List.generate(
          ContentType.maxFields + 3,
          (i) => FieldRule(name: 'f$i', pattern: r'(\d{10})'),
        ),
      );
      expect(greedy.validate(), contains(matches(RegExp('too many fields'))));
      expect(greedy.effectiveFields, hasLength(ContentType.maxFields));

      final chatty = irctcType.copyWith(
        actions: List.generate(
          ContentType.maxActions + 2,
          (i) => ActionTemplate(
              label: 'a$i', uriTemplate: 'https://x.example.com/{pnr}'),
        ),
      );
      expect(chatty.validate(), contains(matches(RegExp('too many actions'))));
      expect(chatty.effectiveActions, hasLength(ContentType.maxActions));
    });
  });

  group('serialization', () {
    test('ContentType survives a JSON round trip', () {
      final restored =
          ContentType.fromJson(jsonDecode(jsonEncode(irctcType.toJson())));
      expect(restored.id, irctcType.id);
      expect(restored.label, irctcType.label);
      expect(restored.produces, ProducesKind.event);
      expect(restored.match.senderDomains, ['irctc.co.in']);
      expect(restored.fields.map((f) => f.name), ['pnr', 'trainNumber']);
      expect(restored.actions.single.kind, 'track');
      expect(restored.learnedByModel, 'claude-haiku-4.5');
      expect(restored.learnedAt, irctcType.learnedAt);
      expect(restored.enabled, isTrue);
    });

    test('fromJson tolerates missing and wrong-typed members', () {
      final restored = ContentType.fromJson(const {
        'id': 'partial',
        'label': 'Partial',
        'match': {'senderDomains': 'not-a-list'},
        'produces': 'nonsense',
        'fields': 'not-a-list',
        'learnedAt': 'not-a-date',
        'matchCount': 'seven',
      });
      expect(restored.id, 'partial');
      expect(restored.match.senderDomains, isEmpty);
      expect(restored.produces, ProducesKind.generic);
      expect(restored.fields, isEmpty);
      expect(restored.matchCount, 0);
      expect(restored.enabled, isTrue);
    });

    test('Playbook.fromJson drops undecodable entries but keeps the rest', () {
      final book = Playbook.fromJson({
        'types': [irctcType.toJson(), 'garbage', 42],
      });
      expect(book.types.map((t) => t.id), ['irctc-eticket']);
    });
  });

  group('KnowledgeStore', () {
    test('load returns an empty playbook when nothing is stored', () async {
      final store = KnowledgeStore();
      expect((await store.load()).isEmpty, isTrue);
    });

    test('round-trips a playbook through SharedPreferences', () async {
      final store = KnowledgeStore();
      await store.save(const Playbook().upsert(irctcType));

      final loaded = await store.load();
      expect(loaded.types, hasLength(1));
      final restored = loaded.byId('irctc-eticket')!;
      expect(restored.label, 'IRCTC e-ticket');
      // The reloaded entry still works as an engine, not just as data.
      expect(loaded.apply(irctcEmail)!.fields['pnr'], '4512345678');
    });

    test('corrupt stored data falls back to an empty playbook', () async {
      SharedPreferences.setMockInitialValues({'playbook_v1': 'not json {{{'});
      expect((await KnowledgeStore().load()).isEmpty, isTrue);

      SharedPreferences.setMockInitialValues({'playbook_v1': '[1,2,3]'});
      expect((await KnowledgeStore().load()).isEmpty, isTrue);
    });

    test('clear removes the stored playbook', () async {
      final store = KnowledgeStore();
      await store.save(const Playbook().upsert(irctcType));
      await store.clear();
      expect((await store.load()).isEmpty, isTrue);
    });
  });
}
