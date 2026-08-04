import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/ai_status.dart';

/// Swaps out Dio's transport entirely, so nothing in this file can reach the
/// network. Every test drives the service through canned bytes or a thrown
/// error instead.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

/// A JSON response with the given status.
ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

AiStatusService _service(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio()..httpClientAdapter = _MockAdapter(handler);
  return AiStatusService(dio: dio);
}

const _testKey = 'sk-or-v1-testkey1234567890abcd';

void _withKey() => dotenv.testLoad(fileInput: 'OPENROUTER_API_KEY=$_testKey');
void _withoutKey() => dotenv.testLoad(fileInput: '');

AiKeyUsage _usage({double? limit, double usage = 0.42}) => AiKeyUsage(
      usage: usage,
      usageDaily: 0.05,
      usageMonthly: usage,
      limit: limit,
      limitRemaining: limit == null ? null : limit - usage,
      isFreeTier: false,
      label: 'NoMail',
    );

void main() {
  group('configuration', () {
    test('maskedKey shows only the prefix and last four characters', () {
      _withKey();
      // Enough to identify the key, useless to anyone reading a screenshot.
      expect(AiStatusService().maskedKey, 'sk-or-…abcd');
      expect(AiStatusService().maskedKey, isNot(contains('testkey')));
    });

    test('maskedKey is null when no key is configured', () {
      _withoutKey();
      expect(AiStatusService().maskedKey, isNull);
    });

    test('isConfigured reflects whether a key is present', () {
      _withKey();
      expect(AiStatusService().isConfigured, isTrue);
      _withoutKey();
      expect(AiStatusService().isConfigured, isFalse);
    });

    test('model falls back to the shared default, and honours an override', () {
      _withKey();
      expect(AiStatusService().model, 'anthropic/claude-haiku-4.5');

      dotenv.testLoad(
        fileInput: 'OPENROUTER_API_KEY=$_testKey\n'
            'OPENROUTER_MODEL=anthropic/claude-sonnet-5',
      );
      expect(AiStatusService().model, 'anthropic/claude-sonnet-5');
    });
  });

  group('AiKeyUsage', () {
    test('spendSummary reports monthly burn when there is no cap', () {
      expect(_usage().spendSummary, '\$0.42 this month');
    });

    test('spendSummary reports spend against the cap when one is set', () {
      expect(_usage(limit: 10).spendSummary, '\$0.42 of \$10.00 used');
    });

    test('warning appears only when the key has no spend limit', () {
      expect(_usage().hasSpendCap, isFalse);
      expect(_usage().warning, 'No spend limit set on this key');

      expect(_usage(limit: 10).hasSpendCap, isTrue);
      expect(_usage(limit: 10).warning, isNull);
    });
  });

  group('AiConnectionResult', () {
    test('summary shows latency on success', () {
      const result = AiConnectionResult(
        ok: true,
        latency: Duration(milliseconds: 420),
        model: 'anthropic/claude-sonnet-5',
      );
      expect(result.summary, 'Connected · 420 ms');
    });

    test('summary shows the human reason on failure', () {
      const result = AiConnectionResult(ok: false, error: 'Out of credits');
      expect(result.summary, 'Out of credits');
    });
  });

  group('fetchUsage', () {
    test('parses the key payload', () async {
      _withKey();
      final service = _service((_) async => _json({
            'data': {
              'label': 'NoMail',
              'usage': 0.42,
              'limit': 10.0,
              'limit_remaining': 9.58,
              'is_free_tier': false,
              'usage_daily': 0.05,
              'usage_weekly': 0.2,
              'usage_monthly': 0.42,
            }
          }));

      final usage = await service.fetchUsage();
      expect(usage, isNotNull);
      expect(usage!.label, 'NoMail');
      expect(usage.usage, 0.42);
      expect(usage.limit, 10.0);
      expect(usage.limitRemaining, 9.58);
      expect(usage.isFreeTier, isFalse);
      expect(usage.spendSummary, '\$0.42 of \$10.00 used');
    });

    test('a null limit is read as "no spend cap"', () async {
      _withKey();
      final service = _service((_) async => _json({
            'data': {
              'label': 'NoMail',
              'usage': 0.42,
              'limit': null,
              'limit_remaining': null,
              'is_free_tier': true,
              'usage_daily': 0.05,
              'usage_monthly': 0.42,
            }
          }));

      final usage = await service.fetchUsage();
      expect(usage!.hasSpendCap, isFalse);
      expect(usage.warning, isNotNull);
    });

    test('returns null on a malformed body rather than throwing', () async {
      _withKey();
      final service = _service((_) async => _json({'nonsense': true}));
      expect(await service.fetchUsage(), isNull);
    });

    test('returns null on an error status rather than throwing', () async {
      _withKey();
      final service = _service(
        (_) async => _json({'error': 'nope'}, status: 401),
      );
      expect(await service.fetchUsage(), isNull);
    });
  });

  group('testConnection', () {
    test('reports success and a measured latency', () async {
      _withKey();
      final service = _service((_) async => _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'OK'}
              }
            ]
          }));

      final result = await service.testConnection();
      expect(result.ok, isTrue);
      expect(result.model, 'anthropic/claude-haiku-4.5');
      expect(result.latency, isNotNull);
      expect(result.summary, startsWith('Connected · '));
    });

    test('sends a deliberately tiny request', () async {
      _withKey();
      late Map<String, dynamic> sent;
      final service = _service((options) async {
        sent = (options.data as Map).cast<String, dynamic>();
        return _json({
          'choices': [
            {'message': {'content': 'OK'}}
          ]
        });
      });

      await service.testConnection();
      // A connection test the user taps repeatedly must stay near-free.
      expect(sent['max_tokens'], lessThanOrEqualTo(5));
      expect((sent['messages'] as List), hasLength(1));
    });

    test('maps 401 to a message naming the thing to fix', () async {
      _withKey();
      final service = _service(
        (_) async => _json({'error': 'unauthorized'}, status: 401),
      );

      final result = await service.testConnection();
      expect(result.ok, isFalse);
      expect(result.error, 'Key rejected — check your OpenRouter key');
    });

    test('maps 429 to a rate-limit message', () async {
      _withKey();
      final service = _service(
        (_) async => _json({'error': 'slow down'}, status: 429),
      );

      final result = await service.testConnection();
      expect(result.ok, isFalse);
      expect(result.error, 'Rate limited, try again shortly');
    });

    test('maps 402 to an out-of-credits message', () async {
      _withKey();
      final service = _service(
        (_) async => _json({'error': 'payment required'}, status: 402),
      );
      expect((await service.testConnection()).error, 'Out of credits');
    });

    test('returns ok:false instead of throwing when the transport fails',
        () async {
      _withKey();
      final service = _service((_) async => throw Exception('boom'));

      // The whole point of the never-throw contract: Settings must survive
      // a transport that blows up.
      final result = await service.testConnection();
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('does not hit the network at all when unconfigured', () async {
      _withoutKey();
      var called = false;
      final service = _service((_) async {
        called = true;
        return _json({});
      });

      final result = await service.testConnection();
      expect(result.ok, isFalse);
      expect(result.error, contains('OpenRouter key'));
      expect(called, isFalse);
    });
  });

  group('modelOptions', () {
    test('is a non-empty catalog of unique slugs with labels and notes', () {
      expect(AiStatusService.modelOptions, isNotEmpty);

      final slugs = AiStatusService.modelOptions.map((o) => o.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));

      for (final option in AiStatusService.modelOptions) {
        expect(option.slug, contains('/'));
        expect(option.label, isNotEmpty);
        expect(option.note, isNotEmpty);
      }
    });

    test('offers at least one non-Anthropic option', () {
      // A picker listing one vendor is a recommendation, not a choice.
      expect(
        AiStatusService.modelOptions
            .any((o) => !o.slug.startsWith('anthropic/')),
        isTrue,
      );
    });
  });
}
