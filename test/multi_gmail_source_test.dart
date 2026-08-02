/// Proves the multi-account merge: ids are namespaced per account so they never
/// collide, and one failing inbox is skipped rather than sinking the sync.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:hmail/data/mail/multi_gmail_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A Gmail-shaped mock: every message-list query returns the single id [msgId]
/// (so within-account dedupe collapses to one), and every get returns a minimal
/// full message for it.
GmailApi _fakeApi(String msgId) {
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/messages')) {
      return http.Response(
        jsonEncode({
          'messages': [
            {'id': msgId},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    // messages/{id}
    return http.Response(
      jsonEncode({
        'id': msgId,
        'snippet': 'hello from $msgId',
        'internalDate': '1700000000000',
        'payload': {
          'headers': [
            {'name': 'From', 'value': 'Sender <s@example.com>'},
            {'name': 'Subject', 'value': 'Subject $msgId'},
          ],
          'mimeType': 'text/plain',
          'body': {'data': base64Url.encode(utf8.encode('body $msgId'))},
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return GmailApi(client);
}

/// An api whose every request throws — stands in for an expired/broken inbox.
GmailApi _throwingApi() {
  final client = MockClient((request) async => throw Exception('boom'));
  return GmailApi(client);
}

void main() {
  test('two accounts sharing a Gmail id yield two namespaced candidates',
      () async {
    // Both inboxes return the same raw id 'm1' — collisions are guaranteed
    // unless the source namespaces per account.
    final source = MultiGmailSource([_fakeApi('m1'), _fakeApi('m1')]);
    final results = await source.fetchCandidates();

    expect(results, hasLength(2));
    expect(results.map((e) => e.id), containsAll(['a0:m1', 'a1:m1']));
    // Ids are globally unique after prefixing.
    expect(results.map((e) => e.id).toSet(), hasLength(2));
  });

  test('a throwing account is skipped, the rest still contribute', () async {
    final source = MultiGmailSource([
      _fakeApi('m1'),
      _throwingApi(),
      _fakeApi('m2'),
    ]);
    final results = await source.fetchCandidates();

    expect(results.map((e) => e.id), ['a0:m1', 'a2:m2']);
  });

  test('no accounts means no candidates', () async {
    final results = await MultiGmailSource(const []).fetchCandidates();
    expect(results, isEmpty);
  });
}
