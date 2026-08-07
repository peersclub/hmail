/// The in-app reader: how a tap gets routed to it, and how it finds a body.
///
/// "Open email" is the most-tapped action in the app and the one with no
/// working hand-off on iOS, so the rules that decide where it goes are pinned
/// here rather than discovered on a device.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:hmail/data/mail/message_reader.dart';
import 'package:hmail/data/mail/multi_gmail_source.dart';
import 'package:hmail/domain/actions.dart';
import 'package:hmail/domain/deep_links.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A Gmail api that answers every message fetch with an HTML body naming
/// [account], so a misrouted fetch is visible rather than merely wrong.
GmailApi _api(String account, {Set<String> has = const {}}) =>
    GmailApi(MockClient((request) async {
      final id = request.url.path.split('/').last;
      if (has.isNotEmpty && !has.contains(id)) {
        return http.Response('{"error":{"code":404}}', 404,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
        jsonEncode({
          'id': id,
          'internalDate': '1754006400000',
          'payload': {
            'mimeType': 'text/html',
            'headers': [
              {'name': 'From', 'value': '$account <$account@example.com>'},
              {'name': 'Subject', 'value': 'Message $id'},
            ],
            'body': {
              'data': base64Url.encode(utf8.encode('<p>body of $id</p>')),
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

void main() {
  setUp(messageReader.clear);
  tearDown(() => messageReader.bind(null));

  group('routing "Open email"', () {
    final openEmail = openEmailAction('18c4f2a9b3e01d55');

    test('a signed-in user reads the message in NoMail', () {
      final plan = planFor(openEmail, const {}, canReadEmail: true);
      expect(plan.mode, LinkOpenMode.emailReader);
      expect(plan.opensIn, 'in NoMail');
    });

    test('the reader wins even when the Gmail app is installed', () {
      // Not a preference for our own UI. There is no working hand-off to Gmail
      // on iOS: mail.google.com claims no universal link for it, and the
      // scheme URL that looked like one made Gmail show "unable to understand
      // link" on a real device. The reader always works, so preferring it also
      // makes the tap behave identically on every phone.
      final plan = planFor(openEmail, {'gmail'}, canReadEmail: true);
      expect(plan.mode, LinkOpenMode.emailReader);
      expect(plan.uri, openEmail.uri,
          reason: 'the web URL is still there for the reader\'s own button');
    });

    test('with no backend it is exactly the old behaviour', () {
      // Demo mode, and the moment before the first sync binds a fetcher.
      final plan = planFor(openEmail, const {}, canReadEmail: false);
      expect(plan.mode, LinkOpenMode.systemHandoff);
      expect(plan.uri, openEmail.uri);
    });

    test('canReadEmail defaults to off, so a caller that forgets is safe', () {
      expect(planFor(openEmail, const {}).mode, LinkOpenMode.systemHandoff);
    });

    test('an action with no source id never reaches the reader', () {
      // The reader has nothing to fetch without one, so the guard is what
      // stops it opening a screen that could only say "couldn't load".
      final orphan = InsightAction(
        label: 'Open email',
        uri: Uri.parse('https://mail.google.com/mail/u/0/#all/x'),
        kind: ActionKind.openEmail,
      );
      expect(planFor(orphan, const {}, canReadEmail: true).mode,
          LinkOpenMode.systemHandoff);
    });

    test('other kinds are untouched by the flag', () {
      final track = InsightAction(
        label: 'Track',
        uri: Uri.parse('https://www.delhivery.com/track/package/AWB1'),
        kind: ActionKind.track,
      );
      expect(planFor(track, const {}, canReadEmail: true).mode,
          LinkOpenMode.inAppWebView);
      expect(planFor(track, {'delhivery'}, canReadEmail: true).mode,
          LinkOpenMode.nativeApp);
    });
  });

  group('MessageReader', () {
    test('unbound, it is unavailable and fetches nothing', () async {
      messageReader.bind(null);
      expect(messageReader.isAvailable, isFalse);
      expect(await messageReader.fetch('abc'), isNull);
    });

    test('a body is fetched once and served from cache after', () async {
      var calls = 0;
      messageReader.bind((id) async {
        calls++;
        return MessageBody(
          from: 'a@b.com',
          subject: 'S',
          date: DateTime(2026, 8, 1),
          html: '<p>hi</p>',
          isRichText: true,
        );
      });
      expect((await messageReader.fetch('m1'))?.subject, 'S');
      expect((await messageReader.fetch('m1'))?.subject, 'S');
      expect(calls, 1, reason: 'the second read must not hit the network');
    });

    test('a failed fetch is not cached', () async {
      // Otherwise one flaky moment makes the email permanently unreadable
      // for the rest of the session.
      var calls = 0;
      messageReader.bind((id) async {
        calls++;
        return calls == 1
            ? null
            : MessageBody(
                from: 'a@b.com',
                subject: 'S',
                date: DateTime(2026, 8, 1),
                html: '<p>hi</p>',
                isRichText: true,
              );
      });
      expect(await messageReader.fetch('m1'), isNull);
      expect((await messageReader.fetch('m1'))?.subject, 'S');
    });

    test('rebinding drops the cache', () async {
      // Sign-out and account changes go through bind(). A body held past that
      // point is one account's mail shown while another is signed in.
      messageReader.bind((id) async => MessageBody(
            from: 'first@b.com',
            subject: 'First',
            date: DateTime(2026, 8, 1),
            html: '<p>1</p>',
            isRichText: true,
          ));
      expect((await messageReader.fetch('m1'))?.subject, 'First');

      messageReader.bind((id) async => MessageBody(
            from: 'second@b.com',
            subject: 'Second',
            date: DateTime(2026, 8, 1),
            html: '<p>2</p>',
            isRichText: true,
          ));
      expect((await messageReader.fetch('m1'))?.subject, 'Second');
    });
  });

  group('fetching across accounts', () {
    test('the a<N>: prefix routes to the account the message came from',
        () async {
      // Gmail ids are unique only within an account. Asking the wrong inbox
      // for one either 404s or returns a different person's email, so this is
      // a correctness rule, not a tidiness one.
      final source = MultiGmailSource([_api('acct0'), _api('acct1')]);

      expect((await source.fetchMessageBody('a0:m9'))?.from,
          contains('acct0'));
      expect((await source.fetchMessageBody('a1:m9'))?.from,
          contains('acct1'));
    });

    test('an unprefixed id is account 0', () async {
      final source = MultiGmailSource([_api('acct0'), _api('acct1')]);
      expect((await source.fetchMessageBody('m9'))?.from, contains('acct0'));
    });

    test('an index past the connected accounts yields null, not a crash',
        () async {
      // Insights outlive the account they came from: remove an account and
      // its a2: ids are still in the snapshot until the next full rescan.
      final source = MultiGmailSource([_api('acct0')]);
      expect(await source.fetchMessageBody('a2:m9'), isNull);
    });

    test('a malformed prefix is read as a plain id, not an account', () {
      // `a-1:` cannot match `a(\d+):`, so it is not a prefix at all and the
      // whole string is the message id — which is the safe reading: it asks
      // account 0 for an id that will simply 404, rather than indexing
      // somewhere unintended.
      final source = MultiGmailSource([_api('acct0', has: {'a-1:m9'})]);
      expect(source.fetchMessageBody('a-1:m9'), completes);
    });

    test('a message that no longer exists yields null', () async {
      final source = MultiGmailSource([_api('acct0', has: {'alive'})]);
      expect((await source.fetchMessageBody('a0:alive'))?.subject,
          'Message alive');
      expect(await source.fetchMessageBody('a0:deleted'), isNull);
    });

    test('the body arrives as HTML, and plain text is escaped not flattened',
        () async {
      // The reader renders this. Unlike the extraction path, markup is the
      // point here — but a plain-text message must not be reinterpreted as
      // markup, or an angle bracket in the text becomes an invisible tag.
      final html = MultiGmailSource([_api('acct0')]);
      final body = await html.fetchMessageBody('a0:m1');
      expect(body!.html, '<p>body of m1</p>');
      expect(body.isRichText, isTrue);

      final plainApi = GmailApi(MockClient((request) async => http.Response(
            jsonEncode({
              'id': 'm1',
              'internalDate': '1754006400000',
              'payload': {
                'mimeType': 'text/plain',
                'headers': const [],
                'body': {
                  'data': base64Url.encode(utf8.encode('5 < 6 & "quoted"')),
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          )));
      final plain = await MultiGmailSource([plainApi]).fetchMessageBody('m1');
      expect(plain!.isRichText, isFalse);
      expect(plain.html, '<pre>5 &lt; 6 &amp; &quot;quoted&quot;</pre>');
    });
  });

  group('the web URL addresses a conversation, not a message', () {
    // Gmail's `#all/<id>` fragment takes a *thread* id. For a single-message
    // thread the two ids are equal, which is why passing a message id looks
    // correct on almost all transactional mail — and why a reply chain, where
    // they differ, silently failed to open. A refetch is the only place the
    // thread id is known, so the reader is the only link that can be right.
    GmailApi threadedApi({required String id, required String threadId}) =>
        GmailApi(MockClient((request) async => http.Response(
              jsonEncode({
                'id': id,
                'threadId': threadId,
                'internalDate': '1754006400000',
                'payload': {
                  'mimeType': 'text/html',
                  'headers': const [],
                  'body': {
                    'data': base64Url.encode(utf8.encode('<p>body</p>')),
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            )));

    test('a refetched body carries its thread id', () async {
      final body = await MultiGmailSource([
        threadedApi(id: 'msg9', threadId: 'thread1'),
      ]).fetchMessageBody('a0:msg9');
      expect(body!.threadId, 'thread1');
    });

    test('a message with no thread id degrades to empty, not a crash',
        () async {
      final api = GmailApi(MockClient((request) async => http.Response(
            jsonEncode({
              'id': 'msg9',
              'internalDate': '1754006400000',
              'payload': {
                'mimeType': 'text/plain',
                'headers': const [],
                'body': {'data': base64Url.encode(utf8.encode('hi'))},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          )));
      final body = await MultiGmailSource([api]).fetchMessageBody('m1');
      expect(body!.threadId, isEmpty,
          reason: 'the reader falls back to the message-id URL from here');
    });

    test('gmailWebUrl names the account slot and the id it was given', () {
      expect(gmailWebUrl(account: 2, id: 'thread1').toString(),
          'https://mail.google.com/mail/u/2/#all/thread1');
    });

    test('splitSourceEmailId recovers the account for the URL', () {
      expect(splitSourceEmailId('a3:msg9'), (account: 3, id: 'msg9'));
      expect(splitSourceEmailId('demo-netflix'),
          (account: 0, id: 'demo-netflix'),
          reason: 'unprefixed ids are account 0, not an error');
    });

    test('a stored insight still yields the message-id URL', () {
      // Unchanged on purpose: extraction never captured a thread id, and it is
      // not worth a network call for a link that only runs when the reader
      // cannot. This pins that the fallback did not regress.
      expect(openEmailAction('a1:msg9').uri.toString(),
          'https://mail.google.com/mail/u/1/#all/msg9');
    });
  });

  group('escapeHtml', () {
    test('ampersand is escaped first so escapes are not re-escaped', () {
      expect(escapeHtml('a & b < c'), 'a &amp; b &lt; c');
      expect(escapeHtml('&lt;'), '&amp;lt;',
          reason: 'text that already looks escaped is still literal text');
    });
  });
}
