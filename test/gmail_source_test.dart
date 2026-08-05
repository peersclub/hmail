/// Pins the Phase A hardening of the Gmail fetch layer: pagination walks
/// nextPageToken up to the per-query cap, quota hiccups (429 / 403 rate
/// limits / 5xx) are retried with backoff instead of killing the scan, and
/// a Retry-After header sets the pace when the server sends one.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:hmail/data/mail/gmail_source.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One query (packages) keeps request counting easy to reason about.
const _onlyPackages = ScanSettings(
  scanMoney: false,
  scanDeliveries: true,
  scanEvents: false,
  scanReads: false,
  scanTravel: false,
);

http.Response _json(
  Map<String, dynamic> body, {
  int status = 200,
  Map<String, String> headers = const {},
}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

Map<String, dynamic> _list(List<String> ids, {String? nextPageToken}) => {
      'messages': [
        for (final id in ids) {'id': id},
      ],
      if (nextPageToken != null) 'nextPageToken': nextPageToken,
    };

Map<String, dynamic> _fullMessage(String id) => {
      'id': id,
      'snippet': 'hello from $id',
      'internalDate': '1754006400000',
      'payload': {
        'headers': [
          {'name': 'From', 'value': 'Shop <ship@example.com>'},
          {'name': 'Subject', 'value': 'Shipped: your order $id'},
        ],
        'mimeType': 'text/plain',
        'body': {'data': base64Url.encode(utf8.encode('body $id'))},
      },
    };

/// A Gmail-style error body; [reason] fills the errors list the way real
/// quota responses do ('rateLimitExceeded' / 'userRateLimitExceeded').
Map<String, dynamic> _apiError(int code,
        {String? reason, String message = 'error'}) =>
    {
      'error': {
        'code': code,
        'message': message,
        if (reason != null)
          'errors': [
            {'domain': 'usageLimits', 'reason': reason, 'message': message},
          ],
      },
    };

bool _isList(http.Request request) =>
    request.url.path.endsWith('/messages') &&
    !request.url.path.contains('/messages/');

void main() {
  test('pagination follows nextPageToken and stops at the cap', () async {
    final listCalls = <Map<String, String>>[];
    final gets = <String>[];
    final client = MockClient((request) async {
      if (_isList(request)) {
        listCalls.add(request.url.queryParameters);
        final token = request.url.queryParameters['pageToken'];
        if (token == null) {
          return _json(_list(['m1', 'm2', 'm3'], nextPageToken: 'page2'));
        }
        // Over-replies (3 ids against maxResults 2, plus another token) to
        // prove the cap is enforced client-side, not just requested.
        return _json(_list(['m4', 'm5', 'm6'], nextPageToken: 'page3'));
      }
      final id = request.url.path.split('/').last;
      gets.add(id);
      return _json(_fullMessage(id));
    });

    final source = GmailSource(GmailApi(client),
        settings: _onlyPackages, perQueryCap: 5);
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(5));
    expect(listCalls, hasLength(2),
        reason: 'cap reached on page two — page3 must never be requested');
    expect(listCalls[0]['maxResults'], '5');
    expect(listCalls[0].containsKey('pageToken'), isFalse);
    expect(listCalls[1]['maxResults'], '2',
        reason: 'later pages only ask for what the cap still allows');
    expect(listCalls[1]['pageToken'], 'page2');
    expect(gets, ['m1', 'm2', 'm3', 'm4', 'm5'],
        reason: 'the ref beyond the cap is never fetched');
    expect(source.failures, 0);
  });

  test('default per-query behaviour is unchanged: one page of 25', () async {
    final listCalls = <Map<String, String>>[];
    final client = MockClient((request) async {
      if (_isList(request)) {
        listCalls.add(request.url.queryParameters);
        return _json(_list(['m1']));
      }
      return _json(_fullMessage('m1'));
    });

    final emails =
        await GmailSource(GmailApi(client), settings: _onlyPackages)
            .fetchCandidates();

    expect(emails, hasLength(1));
    expect(listCalls, hasLength(1),
        reason: 'no nextPageToken means no second request');
    expect(listCalls.single['maxResults'], '25');
    expect(listCalls.single.containsKey('pageToken'), isFalse);
  });

  test('a 429 on the search is retried and succeeds', () async {
    var listCalls = 0;
    final client = MockClient((request) async {
      if (_isList(request)) {
        listCalls++;
        if (listCalls == 1) {
          return _json(_apiError(429, message: 'Resource exhausted'),
              status: 429);
        }
        return _json(_list(['m1']));
      }
      return _json(_fullMessage('m1'));
    });

    final delays = <Duration>[];
    final source = GmailSource(GmailApi(client),
        settings: _onlyPackages, sleep: (d) async => delays.add(d));
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(1));
    expect(source.failures, 0, reason: 'a recovered request is not a failure');
    expect(delays, [const Duration(seconds: 1)]);
  });

  test('a 403 rate limit is retried like a 429', () async {
    var listCalls = 0;
    final client = MockClient((request) async {
      if (_isList(request)) {
        listCalls++;
        if (listCalls == 1) {
          return _json(
              _apiError(403,
                  reason: 'userRateLimitExceeded', message: 'User-rate limit'),
              status: 403);
        }
        return _json(_list(['m1']));
      }
      return _json(_fullMessage('m1'));
    });

    final delays = <Duration>[];
    final source = GmailSource(GmailApi(client),
        settings: _onlyPackages, sleep: (d) async => delays.add(d));
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(1));
    expect(delays, [const Duration(seconds: 1)]);
  });

  test('a plain 403 is not retried — permissions do not heal', () async {
    var m2Attempts = 0;
    final client = MockClient((request) async {
      if (_isList(request)) return _json(_list(['m1', 'm2']));
      final id = request.url.path.split('/').last;
      if (id == 'm2') {
        m2Attempts++;
        return _json(_apiError(403, message: 'Forbidden'), status: 403);
      }
      return _json(_fullMessage(id));
    });

    final delays = <Duration>[];
    final source = GmailSource(GmailApi(client),
        settings: _onlyPackages, sleep: (d) async => delays.add(d));
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(1));
    expect(source.failures, 1);
    expect(m2Attempts, 1, reason: 'no retry budget spent on a hard no');
    expect(delays, isEmpty);
  });

  test('a permanently failing message.get is skipped after 3 retries',
      () async {
    var m2Attempts = 0;
    final client = MockClient((request) async {
      if (_isList(request)) return _json(_list(['m1', 'm2', 'm3']));
      final id = request.url.path.split('/').last;
      if (id == 'm2') {
        m2Attempts++;
        return _json(_apiError(500, message: 'Backend error'), status: 500);
      }
      return _json(_fullMessage(id));
    });

    final delays = <Duration>[];
    final source = GmailSource(GmailApi(client),
        settings: _onlyPackages, sleep: (d) async => delays.add(d));
    final emails = await source.fetchCandidates();

    expect(emails.map((e) => e.id), ['m1', 'm3'],
        reason: 'only the dead message drops out');
    expect(source.failures, 1);
    expect(m2Attempts, 4, reason: 'initial try plus three retries');
    expect(delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

  test('a query dead even after retries is skipped, others contribute',
      () async {
    // Deliveries first, reads second; the deliveries search always 503s.
    final client = MockClient((request) async {
      if (_isList(request)) {
        if ((request.url.queryParameters['q'] ?? '').contains('shipped')) {
          return _json(_apiError(503, message: 'Service unavailable'),
              status: 503);
        }
        return _json(_list(['m9']));
      }
      return _json(_fullMessage('m9'));
    });

    final details = <String>[];
    final source = GmailSource(
      GmailApi(client),
      settings: const ScanSettings(
        scanMoney: false,
        scanDeliveries: true,
        scanEvents: false,
        scanReads: true,
        scanTravel: false,
      ),
      sleep: (_) async {},
    );
    final emails = await source.fetchCandidates(onProgress: details.add);

    expect(emails.map((e) => e.id), ['m9'],
        reason: 'the reads query survives the packages outage');
    expect(source.failures, 1);
    expect(details.any((d) => d.contains('packages') && d.contains('failed')),
        isTrue, reason: 'narration still says what was lost');
  });

  test('Retry-After sets the wait instead of the exponential guess', () async {
    var listCalls = 0;
    final inner = MockClient((request) async {
      if (_isList(request)) {
        listCalls++;
        if (listCalls == 1) {
          return _json(_apiError(429, message: 'Slow down'),
              status: 429, headers: {'retry-after': '7'});
        }
        return _json(_list(['m1']));
      }
      return _json(_fullMessage('m1'));
    });

    final tap = RetryAfterClient(inner);
    final delays = <Duration>[];
    final source = GmailSource(
      GmailApi(tap),
      settings: _onlyPackages,
      retryAfterSource: tap,
      sleep: (d) async => delays.add(d),
    );
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(1));
    expect(delays, [const Duration(seconds: 7)],
        reason: 'the server said 7s, not our 1s guess');
  });

  test('backoff falls back to exponential once Retry-After disappears',
      () async {
    var listCalls = 0;
    final inner = MockClient((request) async {
      if (_isList(request)) {
        listCalls++;
        if (listCalls == 1) {
          return _json(_apiError(429, message: 'Slow down'),
              status: 429, headers: {'retry-after': '3'});
        }
        if (listCalls == 2) {
          // Throttled again, but this time the server names no delay.
          return _json(_apiError(429, message: 'Slow down'), status: 429);
        }
        return _json(_list(['m1']));
      }
      return _json(_fullMessage('m1'));
    });

    final tap = RetryAfterClient(inner);
    final delays = <Duration>[];
    final source = GmailSource(
      GmailApi(tap),
      settings: _onlyPackages,
      retryAfterSource: tap,
      sleep: (d) async => delays.add(d),
    );
    final emails = await source.fetchCandidates();

    expect(emails, hasLength(1));
    expect(delays, [const Duration(seconds: 3), const Duration(seconds: 2)],
        reason: 'a stale Retry-After must not outlive its response');
  });
}
