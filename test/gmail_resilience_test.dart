/// A scan is hundreds of requests over a phone's network, so individual
/// failures are normal. These pin the behaviour that turns "Sync failed:
/// ClientException: Bad file descriptor" into a scan that simply finishes.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:hmail/data/mail/gmail_source.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:http/http.dart' as http;

/// Serves canned Gmail JSON, failing whichever requests the test asks it to.
class FakeGmailClient extends http.BaseClient {
  /// Called with each request; return an exception to throw, or null to serve.
  final Object? Function(int callIndex, Uri url) failWith;
  int calls = 0;
  final List<Uri> seen = [];

  FakeGmailClient(this.failWith);

  static const _messageIds = ['m1', 'm2', 'm3'];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final index = calls++;
    seen.add(request.url);

    final failure = failWith(index, request.url);
    if (failure != null) throw failure;

    final path = request.url.path;
    final body = path.endsWith('/messages')
        ? jsonEncode({
            'messages': [for (final id in _messageIds) {'id': id}],
          })
        : jsonEncode({
            'id': path.split('/').last,
            'internalDate': '1754006400000',
            'snippet': 'hello',
            'payload': {
              'headers': [
                {'name': 'From', 'value': 'Shop <ship@example.com>'},
                {'name': 'Subject', 'value': 'Shipped: your order'},
              ],
              'mimeType': 'text/plain',
              'body': {
                'data': base64Url.encode(utf8.encode('Your package shipped.')),
              },
            },
          });

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

GmailSource sourceWith(FakeGmailClient client) => GmailSource(
      GmailApi(client),
      // One query keeps the call counting easy to reason about.
      settings: const ScanSettings(
        scanMoney: false,
        scanEvents: false,
        scanDeliveries: true,
      ),
    );

void main() {
  test('a healthy scan returns every message', () async {
    final client = FakeGmailClient((_, __) => null);
    final source = sourceWith(client);

    final emails = await source.fetchCandidates();

    expect(emails, hasLength(3));
    expect(source.failures, 0);
  });

  test('one dead message does not abort the scan', () async {
    // Call 0 lists; calls 1..3 fetch messages. Kill the second fetch.
    final client = FakeGmailClient((index, _) => index == 2
        ? http.ClientException('Bad file descriptor')
        : null);
    final source = sourceWith(client);

    final emails = await source.fetchCandidates();

    expect(emails, hasLength(2), reason: 'the other two still arrive');
    expect(source.failures, 1);
  });

  test('a dead query is skipped rather than fatal', () async {
    final client = FakeGmailClient((index, url) =>
        url.path.endsWith('/messages') && !url.path.contains('/messages/')
            ? http.ClientException('Bad file descriptor')
            : null);
    final source = sourceWith(client);

    // The only query fails, so nothing is fetched at all — that is a broken
    // sync, not a partial one, and must surface.
    await expectLater(
      source.fetchCandidates(),
      throwsA(isA<StateError>()),
    );
  });

  test('total failure surfaces instead of reporting an empty inbox', () async {
    final client =
        FakeGmailClient((_, __) => http.ClientException('Bad file descriptor'));

    await expectLater(
      sourceWith(client).fetchCandidates(),
      throwsA(predicate((e) =>
          e is StateError && e.message.contains('Gmail unreachable'))),
    );
  });

  test('failures counter resets between scans', () async {
    var failNext = true;
    final client = FakeGmailClient((index, _) {
      if (failNext && index == 2) return http.ClientException('boom');
      return null;
    });
    final source = sourceWith(client);

    await source.fetchCandidates();
    expect(source.failures, 1);

    failNext = false;
    await source.fetchCandidates();
    expect(source.failures, 0, reason: 'a clean scan must report clean');
  });
}
