import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/knowledge_learner.dart';
import 'package:hmail/domain/knowledge.dart';
import 'package:hmail/domain/models.dart';

/// Replaces Dio's transport, so nothing in this file can reach the network.
/// [calls] is the assertion surface for "did we spend a token at all?".
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// An OpenRouter chat completion whose assistant message is [content].
ResponseBody _completion(String content) => _json({
      'choices': [
        {
          'message': {'content': content}
        }
      ]
    });

/// A learner wired to [handler], plus the adapter so tests can count calls.
({KnowledgeLearner learner, _MockAdapter adapter}) _learner(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final adapter = _MockAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  return (learner: KnowledgeLearner(dio: dio), adapter: adapter);
}

/// A learner that fails the test if the network is touched at all.
({KnowledgeLearner learner, _MockAdapter adapter}) _neverCalled() =>
    _learner((_) async {
      fail('the model must not be called');
    });

EmailMeta _email({
  required String id,
  required String from,
  required String subject,
  String body = '',
  DateTime? date,
}) =>
    EmailMeta(
      id: id,
      from: from,
      subject: subject,
      snippet: body.length > 80 ? body.substring(0, 80) : body,
      body: body,
      date: date ?? DateTime(2026, 8, 1),
    );

/// Two IRCTC e-tickets: a recurring, machine-sent, clearly transactional shape.
List<EmailMeta> _irctcCluster() => [
      _email(
        id: 'm1',
        from: 'noreply@ticketadmin.irctc.co.in',
        subject: 'Booking confirmed — PNR 4512345678',
        body: 'Your e-ticket is confirmed. PNR 4512345678. Train 12951 '
            'Mumbai Central to New Delhi. Do not reply to this email.',
      ),
      _email(
        id: 'm2',
        from: 'noreply@ticketadmin.irctc.co.in',
        subject: 'Booking confirmed — PNR 8899001122',
        body: 'Your e-ticket is confirmed. PNR 8899001122. Train 12009 '
            'Ahmedabad to Mumbai Central. Do not reply to this email.',
      ),
    ];

/// A well-formed entry for the IRCTC cluster; [overrides] mutate one field so
/// each safety test differs from the happy path in exactly one way.
Map<String, dynamic> _entry([Map<String, dynamic> overrides = const {}]) => {
      'cluster': 'ticketadmin.irctc.co.in',
      'id': 'irctc-eticket',
      'label': 'IRCTC e-ticket',
      'match': {
        'senderDomains': ['irctc.co.in'],
        'subjectAny': ['booking confirmed'],
        'bodyAll': <String>[],
      },
      'produces': 'event',
      'fields': [
        {'name': 'pnr', 'pattern': r'\b([0-9]{10})\b', 'nearKeyword': 'PNR'}
      ],
      'actions': [
        {
          'label': 'Check PNR status',
          'uriTemplate': 'https://www.irctc.co.in/online-charts/pnr/{pnr}',
          'kind': 'openLink',
        }
      ],
      ...overrides,
    };

String _reply(List<Map<String, dynamic>> types) => jsonEncode({'types': types});

const _testKey = 'sk-or-v1-testkey1234567890abcd';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'OPENROUTER_API_KEY=$_testKey');
  });

  setUp(() {
    // Each test starts from the configured default; the unconfigured test
    // overrides it locally.
    dotenv.testLoad(fileInput: 'OPENROUTER_API_KEY=$_testKey');
  });

  group('spending nothing', () {
    test('emails the playbook already knows are never sent to the model',
        () async {
      final known = Playbook(types: [
        ContentType(
          id: 'irctc-eticket',
          label: 'IRCTC e-ticket',
          match: const ContentMatcher(senderDomains: ['irctc.co.in']),
          learnedAt: DateTime(2026, 7, 1),
        ),
      ]);

      final fixture = _neverCalled();
      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: known);

      expect(fixture.adapter.calls, isEmpty);
      expect(result.types, isEmpty);
      expect(result.error, isNull);
    });

    test('a disabled entry still counts as known, so it is not relearned',
        () async {
      final known = Playbook(types: [
        ContentType(
          id: 'irctc-eticket',
          label: 'IRCTC e-ticket',
          match: const ContentMatcher(senderDomains: ['irctc.co.in']),
          learnedAt: DateTime(2026, 7, 1),
          enabled: false,
        ),
      ]);

      final fixture = _neverCalled();
      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: known);

      expect(fixture.adapter.calls, isEmpty);
      expect(result.types, isEmpty);
    });

    test('marketing-only senders are not worth a request', () async {
      final newsletter = [
        _email(
          id: 'n1',
          from: 'hello@deals.example.com',
          subject: 'Flash sale — 40% off everything',
          body: 'Our biggest sale of the year. Shop now, limited time offer.',
        ),
        _email(
          id: 'n2',
          from: 'hello@deals.example.com',
          subject: 'Weekly roundup from the blog',
          body: 'This week: a newsletter of exclusive deals and discount '
              'coupons.',
        ),
      ];

      final fixture = _neverCalled();
      final result = await fixture.learner
          .learn(unclaimed: newsletter, known: Playbook.empty);

      expect(fixture.adapter.calls, isEmpty);
      expect(result.types, isEmpty);
    });

    test('an unconfigured learner returns empty without any network call',
        () async {
      dotenv.testLoad(fileInput: '');

      final fixture = _neverCalled();
      expect(fixture.learner.isConfigured, isFalse);

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(fixture.adapter.calls, isEmpty);
      expect(result.types, isEmpty);
      expect(result.error, contains('OPENROUTER_API_KEY'));
    });
  });

  group('clustering', () {
    test('two emails from the same sender become one cluster', () async {
      late String prompt;
      final fixture = _learner((options) async {
        prompt = (options.data as Map)['messages'][0]['content'] as String;
        return _completion(_reply([_entry()]));
      });

      await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(fixture.adapter.calls, hasLength(1));
      // One cluster header, carrying both sampled emails.
      expect('--- cluster'.allMatches(prompt).length, 1);
      expect(prompt, contains('cluster "ticketadmin.irctc.co.in" (2 email(s))'));
      expect(prompt, contains('PNR 4512345678'));
      expect(prompt, contains('PNR 8899001122'));
    });

    test('maxNewTypes caps both the clusters sent and the entries accepted',
        () async {
      final unclaimed = [
        ..._irctcCluster(),
        _email(
          id: 'b1',
          from: 'billing@bescom.co.in',
          subject: 'Your electricity bill is due',
          body: 'Amount due Rs. 1,840.50. Payment due by 15 Aug 2026. '
              'This is an automated message.',
        ),
        _email(
          id: 'b2',
          from: 'billing@bescom.co.in',
          subject: 'Your electricity bill is due',
          body: 'Amount due Rs. 2,010.00. Payment due by 15 Sep 2026. '
              'This is an automated message.',
        ),
      ];

      late String prompt;
      final fixture = _learner((options) async {
        prompt = (options.data as Map)['messages'][0]['content'] as String;
        // The model over-delivers; the budget still holds.
        return _completion(_reply([
          _entry(),
          _entry({'id': 'irctc-eticket-2'}),
        ]));
      });

      final result = await fixture.learner.learn(
        unclaimed: unclaimed,
        known: Playbook.empty,
        maxNewTypes: 1,
      );

      expect('--- cluster'.allMatches(prompt).length, 1);
      expect(result.types, hasLength(1));
      expect(result.skipped.single, contains('budget'));
    });
  });

  group('accepting good knowledge', () {
    test('a well-formed reply yields a valid entry with provenance filled in',
        () async {
      final fixture = _learner((_) async => _completion(_reply([_entry()])));

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.error, isNull);
      expect(result.skipped, isEmpty);
      expect(result.types, hasLength(1));

      final type = result.types.single;
      expect(type.id, 'irctc-eticket');
      expect(type.produces, ProducesKind.event);
      expect(type.validate(), isEmpty);
      expect(type.learnedFromEmailId, 'm1');
      expect(type.learnedByModel, 'anthropic/claude-haiku-4.5');
      expect(type.learnedAt.isAfter(DateTime(2026, 1, 1)), isTrue);
      expect(type.matchCount, 0);
      expect(type.enabled, isTrue);

      // The entry must actually work on the email it was learned from.
      final hit = Playbook(types: result.types).apply(_irctcCluster().first);
      expect(hit, isNotNull);
      expect(hit!.fields['pnr'], '4512345678');
      expect(hit.actions.single.uri.toString(),
          'https://www.irctc.co.in/online-charts/pnr/4512345678');
    });

    test('a fenced JSON reply is still parsed', () async {
      final fixture = _learner(
        (_) async => _completion('```json\n${_reply([_entry()])}\n```'),
      );

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.types, hasLength(1));
      expect(result.error, isNull);
    });
  });

  group('safety rejections', () {
    Future<LearnedTypes> reject(Map<String, dynamic> overrides) async {
      final fixture =
          _learner((_) async => _completion(_reply([_entry(overrides)])));
      return fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);
    }

    test('a matcher domain absent from the cluster is skipped with a reason',
        () async {
      final result = await reject({
        'match': {
          'senderDomains': ['amazon.in'],
          'subjectAny': ['booking confirmed'],
          'bodyAll': <String>[],
        }
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('amazon.in'));
      expect(result.skipped.single, contains('does not appear in cluster'));
    });

    test('a regex that does not compile is skipped', () async {
      final result = await reject({
        'fields': [
          {'name': 'pnr', 'pattern': r'([0-9]{10}', 'nearKeyword': 'PNR'}
        ]
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('pnr'));
      expect(result.skipped.single, contains('regex'));
    });

    test('a catch-all regex that swallows the email is skipped', () async {
      final result = await reject({
        'fields': [
          {'name': 'pnr', 'pattern': r'PNR(.*)'}
        ]
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('too broad'));
    });

    test('a javascript: uriTemplate is skipped', () async {
      final result = await reject({
        'actions': [
          {
            'label': 'Check PNR status',
            'uriTemplate': 'javascript:steal({pnr})',
            'kind': 'openLink',
          }
        ]
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('Check PNR status'));
    });

    test('a plain http: uriTemplate is skipped', () async {
      final result = await reject({
        'actions': [
          {
            'label': 'Check PNR status',
            'uriTemplate': 'http://www.irctc.co.in/pnr/{pnr}',
            'kind': 'openLink',
          }
        ]
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('https'));
    });

    test('an over-broad matcher with no sender domain is skipped', () async {
      final result = await reject({
        'match': {
          'senderDomains': <String>[],
          'subjectAny': ['confirmed'],
          'bodyAll': <String>[],
        }
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('brand-scoped'));
    });

    test('an invented subject term that matches nothing is skipped', () async {
      final result = await reject({
        'match': {
          'senderDomains': ['irctc.co.in'],
          'subjectAny': ['flight itinerary'],
          'bodyAll': <String>[],
        }
      });

      expect(result.types, isEmpty);
      expect(result.skipped.single,
          contains('does not match any email it was learned from'));
    });

    test('an entry whose id is already in the playbook is skipped', () async {
      final known = Playbook(types: [
        ContentType(
          id: 'irctc-eticket',
          label: 'Existing',
          // Deliberately unrelated so knows() does not short-circuit the call.
          match: const ContentMatcher(senderDomains: ['some-other-brand.com']),
          learnedAt: DateTime(2026, 7, 1),
        ),
      ]);

      final fixture = _learner((_) async => _completion(_reply([_entry()])));
      final result =
          await fixture.learner.learn(unclaimed: _irctcCluster(), known: known);

      expect(result.types, isEmpty);
      expect(result.skipped.single, contains('already exists'));
    });
  });

  group('never throws', () {
    test('a non-JSON reply returns error and no types', () async {
      final fixture = _learner(
        (_) async => _completion('Sure! Here are some content types for you.'),
      );

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.types, isEmpty);
      expect(result.error, contains('valid JSON'));
    });

    test('a network error returns error and no types', () async {
      final fixture = _learner((options) async {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'no route to host',
        );
      });

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.types, isEmpty);
      expect(result.error, isNotNull);
      expect(result.hasError, isTrue);
    });

    test('an HTTP 500 returns error and no types', () async {
      final fixture =
          _learner((_) async => _json({'error': 'boom'}, status: 500));

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.types, isEmpty);
      expect(result.error, contains('500'));
    });

    test('a structurally surprising reply returns error and no types',
        () async {
      final fixture = _learner((_) async => _json({'choices': []}));

      final result = await fixture.learner
          .learn(unclaimed: _irctcCluster(), known: Playbook.empty);

      expect(result.types, isEmpty);
      expect(result.error, isNotNull);
    });
  });
}
