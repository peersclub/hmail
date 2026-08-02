/// Where a tap lands. Getting this wrong is invisible in code review and
/// obvious to a user, so every routing rule is pinned here.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/domain/actions.dart';
import 'package:hmail/domain/deep_links.dart';
import 'package:hmail/ui/action_sheet.dart';

InsightAction action(String url, ActionKind kind, {String label = 'Go'}) =>
    InsightAction(label: label, uri: Uri.parse(url), kind: kind);

void main() {
  group('native app when installed', () {
    test('a tracking link opens Delhivery when Delhivery is present', () {
      final plan = planFor(
        action('https://www.delhivery.com/track/package/AWB123',
            ActionKind.track),
        {'delhivery'},
      );
      expect(plan.mode, LinkOpenMode.nativeApp);
      expect(plan.destination, 'Delhivery');
      expect(plan.appKey, 'delhivery');
      expect(plan.uri.toString(), contains('AWB123'),
          reason: 'we launch the https universal link, not a guessed scheme');
    });

    test('the same link falls to the WebView when the app is absent', () {
      final plan = planFor(
        action('https://www.delhivery.com/track/package/AWB123',
            ActionKind.track),
        const {},
      );
      expect(plan.mode, LinkOpenMode.inAppWebView);
      expect(plan.opensIn, 'in NoMail');
    });

    test('an unrelated installed app does not capture the link', () {
      final plan = planFor(
        action('https://www.delhivery.com/track/x', ActionKind.track),
        {'swiggy', 'uber'},
      );
      expect(plan.mode, LinkOpenMode.inAppWebView);
    });
  });

  group('non-http schemes go to iOS', () {
    test('upi:// is handed off and named', () {
      final plan = planFor(
        action('upi://pay?pa=bescom@icici&am=1840', ActionKind.pay),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
      expect(plan.destination, 'your UPI app');
    });

    test('a known app scheme resolves to that app name', () {
      final plan = planFor(action('uber://?action=setPickup', ActionKind.openLink),
          {'uber'});
      expect(plan.mode, LinkOpenMode.systemHandoff);
      expect(plan.destination, 'Uber');
    });

    test('tel: is never rendered in the WebView', () {
      final plan = planFor(action('tel:+911234567890', ActionKind.openLink),
          const {});
      expect(plan.mode, LinkOpenMode.systemHandoff);
      expect(plan.destination, 'Phone');
    });
  });

  group('login-gated pages never open in our WebView', () {
    test('Gmail goes to the system, not an unauthenticated WebView', () {
      final plan = planFor(
        action('https://mail.google.com/mail/u/0/#all/abc',
            ActionKind.openEmail),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
    });

    test('a subscription billing page goes to the system', () {
      final plan = planFor(
        action('https://www.netflix.com/account', ActionKind.manage),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
    });

    test('a payment host is gated even under a neutral action kind', () {
      final plan = planFor(
        action('https://www.billdesk.com/pay/123', ActionKind.openLink),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff,
          reason: 'a WKWebView has no session, and payments need trust');
    });

    test('subdomains of a gated host are gated too', () {
      final plan = planFor(
        action('https://secure.hdfcbank.com/pay', ActionKind.openLink),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
    });

    test('a lookalike host is NOT gated', () {
      final plan = planFor(
        action('https://nothdfcbank.com.tracking.example/x',
            ActionKind.track),
        const {},
      );
      expect(plan.mode, LinkOpenMode.inAppWebView);
    });
  });

  group('action kind overrides', () {
    test('pay never opens in the WebView, even on a public host', () {
      final plan = planFor(
        action('https://smallbiller.example/pay/9', ActionKind.pay),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
    });

    test('a calendar write is handed off', () {
      final plan = planFor(
        action('https://calendar.google.com/calendar/render?action=TEMPLATE',
            ActionKind.remind),
        const {},
      );
      expect(plan.mode, LinkOpenMode.systemHandoff);
    });

    test('a public tracking page is the WebView case', () {
      final plan = planFor(
        action('https://t.17track.net/en#nums=XYZ', ActionKind.track),
        const {},
      );
      expect(plan.mode, LinkOpenMode.inAppWebView);
    });
  });

  test('an empty installed set still produces a usable plan', () {
    for (final kind in ActionKind.values) {
      final plan = planFor(action('https://example.com/x', kind), const {});
      expect(plan.uri.host, 'example.com');
      expect(plan.destination, isNotEmpty);
    }
  });

  group('destination hint tells the user what happens next', () {
    test('a detected app shows its own name', () {
      final hint = destinationHint(planFor(
        action('https://www.delhivery.com/track/1', ActionKind.track),
        {'delhivery'},
      ));
      expect(hint.label, 'Delhivery');
    });

    test('the WebView case says it stays in NoMail', () {
      final hint = destinationHint(planFor(
        action('https://t.17track.net/en#nums=X', ActionKind.track),
        const {},
      ));
      expect(hint.label, 'in NoMail');
      expect(hint.icon, CupertinoIcons.globe);
    });

    test('leaving the app shows the out-arrow', () {
      final hint = destinationHint(planFor(
        action('https://mail.google.com/mail/u/0/#all/x', ActionKind.openEmail),
        const {},
      ));
      expect(hint.icon, CupertinoIcons.arrow_up_right_square);
    });

    test('a upi intent names the handler rather than a browser', () {
      final hint = destinationHint(planFor(
        action('upi://pay?pa=x@y&am=1', ActionKind.pay),
        const {},
      ));
      expect(hint.label, 'your UPI app');
    });

    test('every mode produces a non-empty label and a distinct icon', () {
      final icons = <IconData>{};
      for (final plan in [
        planFor(action('https://www.delhivery.com/t/1', ActionKind.track),
            {'delhivery'}),
        planFor(action('https://t.17track.net/x', ActionKind.track), const {}),
        planFor(action('https://mail.google.com/x', ActionKind.openEmail),
            const {}),
      ]) {
        final hint = destinationHint(plan);
        expect(hint.label, isNotEmpty);
        icons.add(hint.icon);
      }
      expect(icons, hasLength(3), reason: 'the three outcomes must look different');
    });
  });
}
