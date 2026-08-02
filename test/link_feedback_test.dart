import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/link_feedback_store.dart';
import 'package:hmail/domain/link_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Widget tests for WebViewScreen are deliberately absent. Verified, not
// assumed: pumping it throws in the plugin, not in our code —
//   'WebViewPlatform.instance != null': is not true
//     (platform_webview_controller.dart:27)
// because `WebViewController()` is constructed in initState and WKWebView has
// no implementation in the headless `flutter test` shell. Covering it would
// mean hand-writing a fake WebViewPlatform, at which point the test asserts
// that the fake behaves like the fake. The logic worth testing — outcomes,
// the cap, the suspect heuristic, persistence — lives below, off the widget.

LinkFeedback _fb(
  LinkOutcome outcome, {
  String url = 'https://track.example/awb/1',
  String? knowledgeTypeId = 'kt_courier',
  int minute = 0,
}) =>
    LinkFeedback(
      url: url,
      insightId: 'ins_1',
      sourceEmailId: 'msg_1',
      knowledgeTypeId: knowledgeTypeId,
      outcome: outcome,
      at: DateTime.utc(2026, 8, 1, 10, minute),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LinkFeedback', () {
    test('survives a JSON round-trip unchanged', () {
      final original = _fb(LinkOutcome.wrongPage);
      final restored =
          LinkFeedback.fromJson(jsonDecode(jsonEncode(original.toJson())));

      expect(restored, original);
      expect(restored.url, 'https://track.example/awb/1');
      expect(restored.insightId, 'ins_1');
      expect(restored.sourceEmailId, 'msg_1');
      expect(restored.knowledgeTypeId, 'kt_courier');
      expect(restored.outcome, LinkOutcome.wrongPage);
      expect(restored.at, DateTime.utc(2026, 8, 1, 10, 0));
    });

    test('fromJson tolerates an empty map instead of throwing', () {
      final restored = LinkFeedback.fromJson(const {});

      expect(restored.url, '');
      expect(restored.insightId, isNull);
      expect(restored.sourceEmailId, isNull);
      expect(restored.knowledgeTypeId, isNull);
      expect(restored.outcome, LinkOutcome.dismissed);
      expect(restored.at, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('an unknown outcome name falls back to dismissed', () {
      expect(LinkOutcome.parse('exploded_in_a_new_way'), LinkOutcome.dismissed);
      expect(LinkOutcome.parse(null), LinkOutcome.dismissed);
      expect(LinkOutcome.parse(42), LinkOutcome.dismissed);
      // Known names still parse.
      expect(LinkOutcome.parse('worked'), LinkOutcome.worked);
      expect(LinkOutcome.parse('brokenLink'), LinkOutcome.brokenLink);
    });

    test('copyWith replaces only the named field', () {
      final original = _fb(LinkOutcome.worked);
      final updated = original.copyWith(outcome: LinkOutcome.brokenLink);

      expect(updated.outcome, LinkOutcome.brokenLink);
      expect(updated.url, original.url);
      expect(updated.knowledgeTypeId, original.knowledgeTypeId);
      expect(updated.at, original.at);
    });
  });

  group('LinkFeedbackLog', () {
    test('add appends to the end and leaves the receiver untouched', () {
      const log = LinkFeedbackLog();
      final one = log.add(_fb(LinkOutcome.worked, minute: 1));
      final two = one.add(_fb(LinkOutcome.wrongPage, minute: 2));

      expect(log.entries, isEmpty);
      expect(one.length, 1);
      expect(two.length, 2);
      expect(two.entries.last.outcome, LinkOutcome.wrongPage);
    });

    test('enforces the cap by dropping the oldest entries', () {
      var log = const LinkFeedbackLog();
      for (var i = 0; i < LinkFeedbackLog.maxEntries + 5; i++) {
        log = log.add(_fb(LinkOutcome.worked, url: 'https://x.test/$i'));
      }

      expect(log.length, LinkFeedbackLog.maxEntries);
      // The first five are gone; entry 5 is now the oldest.
      expect(log.entries.first.url, 'https://x.test/5');
      expect(log.entries.last.url,
          'https://x.test/${LinkFeedbackLog.maxEntries + 4}');
      expect(log.forUrl('https://x.test/0'), isEmpty);
    });

    test('forUrl and forKnowledgeType filter independently', () {
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.worked, url: 'https://a.test/1'))
          .add(_fb(LinkOutcome.wrongPage, url: 'https://b.test/2'))
          .add(_fb(LinkOutcome.worked,
              url: 'https://a.test/1', knowledgeTypeId: 'kt_pay'));

      expect(log.forUrl('https://a.test/1').length, 2);
      expect(log.forUrl('https://b.test/2').single.outcome,
          LinkOutcome.wrongPage);
      expect(log.forUrl('https://nothing.test').isEmpty, isTrue);
      expect(log.forKnowledgeType('kt_courier').length, 2);
      expect(log.forKnowledgeType('kt_pay').length, 1);
      expect(log.forKnowledgeType('kt_missing'), isEmpty);
    });

    test('failuresFor counts every non-worked outcome and nothing else', () {
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.worked))
          .add(_fb(LinkOutcome.wrongPage))
          .add(_fb(LinkOutcome.brokenLink))
          .add(_fb(LinkOutcome.dismissed))
          // Different recipe — must not be counted.
          .add(_fb(LinkOutcome.wrongPage, knowledgeTypeId: 'kt_other'));

      expect(log.failuresFor('kt_courier'), 3);
      expect(log.failuresFor('kt_other'), 1);
      expect(log.failuresFor('kt_unknown'), 0);
    });

    test('isSuspect is false after a single failure', () {
      final log = const LinkFeedbackLog().add(_fb(LinkOutcome.wrongPage));

      expect(log.failuresFor('kt_courier'), 1);
      expect(log.isSuspect('kt_courier'), isFalse);
    });

    test('isSuspect is true after two failures with no success', () {
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.wrongPage))
          .add(_fb(LinkOutcome.brokenLink));

      expect(log.isSuspect('kt_courier'), isTrue);
      expect(log.suspectKnowledgeTypes, ['kt_courier']);
    });

    test('a recipe that has ever worked is never suspect', () {
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.wrongPage))
          .add(_fb(LinkOutcome.brokenLink))
          .add(_fb(LinkOutcome.wrongPage))
          .add(_fb(LinkOutcome.worked));

      expect(log.failuresFor('kt_courier'), 3);
      expect(log.isSuspect('kt_courier'), isFalse);
      expect(log.suspectKnowledgeTypes, isEmpty);
    });

    test('isSuspect ignores entries with no knowledge type', () {
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.wrongPage, knowledgeTypeId: null))
          .add(_fb(LinkOutcome.brokenLink, knowledgeTypeId: null));

      expect(log.suspectKnowledgeTypes, isEmpty);
      expect(log.isSuspect('kt_courier'), isFalse);
    });
  });

  group('LinkFeedbackStore', () {
    test('save then load round-trips the log', () async {
      final store = LinkFeedbackStore();
      final log = const LinkFeedbackLog()
          .add(_fb(LinkOutcome.worked, minute: 1))
          .add(_fb(LinkOutcome.wrongPage, minute: 2));

      await store.save(log);
      final loaded = await store.load();

      expect(loaded.length, 2);
      expect(loaded.entries, log.entries);
      expect(loaded.isSuspect('kt_courier'), isFalse);
    });

    test('load returns an empty log when nothing was ever saved', () async {
      final loaded = await LinkFeedbackStore().load();

      expect(loaded.isEmpty, isTrue);
      expect(loaded.entries, isEmpty);
    });

    test('load falls back to empty on corrupt data', () async {
      SharedPreferences.setMockInitialValues({
        'link_feedback_v1': 'not json at all {{{',
      });

      expect((await LinkFeedbackStore().load()).isEmpty, isTrue);

      // Valid JSON of the wrong shape is equally survivable.
      SharedPreferences.setMockInitialValues({
        'link_feedback_v1': '{"entries":"nope"}',
      });
      expect((await LinkFeedbackStore().load()).isEmpty, isTrue);

      // A list with one unusable member keeps the usable ones.
      SharedPreferences.setMockInitialValues({
        'link_feedback_v1': jsonEncode({
          'entries': [
            'garbage',
            {'url': 'https://ok.test', 'outcome': 'worked'},
          ],
        }),
      });
      final salvaged = await LinkFeedbackStore().load();
      expect(salvaged.length, 1);
      expect(salvaged.entries.single.url, 'https://ok.test');
    });

    test('clear removes the stored log', () async {
      final store = LinkFeedbackStore();
      await store.save(const LinkFeedbackLog().add(_fb(LinkOutcome.worked)));
      expect((await store.load()).length, 1);

      await store.clear();
      expect((await store.load()).isEmpty, isTrue);
    });

    test('append reads, adds and persists in one step', () async {
      final store = LinkFeedbackStore();
      await store.append(_fb(LinkOutcome.wrongPage, minute: 1));
      final after = await store.append(_fb(LinkOutcome.brokenLink, minute: 2));

      expect(after.length, 2);
      expect((await store.load()).length, 2);
      expect(after.isSuspect('kt_courier'), isTrue);
    });
  });

  group('login walls must not accuse a recipe', () {
    LinkFeedback fb(LinkOutcome outcome, {String type = 'porter'}) =>
        LinkFeedback(
          url: 'https://porter.example/track/1',
          knowledgeTypeId: type,
          outcome: outcome,
          at: DateTime(2026, 8, 2),
        );

    test('loginWall is not counted as a failure', () {
      expect(LinkOutcome.loginWall.isFailure, isFalse);
      expect(LinkOutcome.wrongPage.isFailure, isTrue);
      expect(LinkOutcome.brokenLink.isFailure, isTrue);
      expect(LinkOutcome.dismissed.isFailure, isTrue);
      expect(LinkOutcome.worked.isFailure, isFalse);
    });

    test('two login walls leave a recipe unsuspected', () {
      final log = const LinkFeedbackLog()
          .add(fb(LinkOutcome.loginWall))
          .add(fb(LinkOutcome.loginWall));
      expect(log.failuresFor('porter'), 0);
      expect(log.isSuspect('porter'), isFalse,
          reason: 'our WebView has no session — that is our limitation, '
              'not evidence the URL is wrong');
    });

    test('a login wall does not mask a genuine failure', () {
      final log = const LinkFeedbackLog()
          .add(fb(LinkOutcome.loginWall))
          .add(fb(LinkOutcome.wrongPage))
          .add(fb(LinkOutcome.wrongPage));
      expect(log.failuresFor('porter'), 2);
      expect(log.isSuspect('porter'), isTrue);
    });

    test('loginWall round-trips through JSON', () {
      final restored = LinkFeedback.fromJson(
          fb(LinkOutcome.loginWall).toJson());
      expect(restored.outcome, LinkOutcome.loginWall);
    });
  });
}
