/// What the extractors get to read.
///
/// Everything downstream — amounts, due dates, tracking links, the AI prompt —
/// sees only the string these functions produce. A regression here is silent:
/// insights simply stop appearing, with no error anywhere.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/extractors/links.dart';
import 'package:hmail/data/mail/html_text.dart';
import 'package:hmail/domain/models.dart';

void main() {
  group('anchors keep their label next to their URL', () {
    test('a button becomes "label url", in that order', () {
      // Order matters: extractActionUrl scores a URL by the action words
      // within ±80 characters of it, and the label is the best such signal
      // in the whole message.
      expect(
        htmlToText('<a href="https://acme.com/track/9">Track your order</a>'),
        'Track your order https://acme.com/track/9',
      );
    });

    test('markup inside the label is flattened, not dropped', () {
      expect(
        htmlToText('<a href="https://x.com/p"><span><b>Pay</b> now</span></a>'),
        'Pay now https://x.com/p',
      );
    });

    test('single quotes and bare hrefs parse too', () {
      expect(htmlToText("<a href='https://a.com/1'>One</a>"),
          'One https://a.com/1');
      expect(htmlToText('<a href=https://b.com/2>Two</a>'),
          'Two https://b.com/2');
    });

    test('an href with attributes after it still resolves', () {
      expect(
        htmlToText('<a href="https://c.com/3" style="color:red" '
            'target="_blank">Three</a>'),
        'Three https://c.com/3',
      );
    });

    test('non-navigating hrefs keep their words and lose their target', () {
      for (final href in ['#top', 'mailto:a@b.com', 'tel:+911234', 'javascript:void(0)']) {
        expect(htmlToText('<a href="$href">Contact us</a>'), 'Contact us',
            reason: 'href was "$href"');
      }
    });
  });

  group('what must never reach the haystack', () {
    test('script and style contents are gone, not just their tags', () {
      // EmailMeta.haystack concatenates the body and every extractor
      // pattern-matches it, so a stylesheet full of class names and a
      // tracker full of URLs would produce false positives app-wide.
      final text = htmlToText('''
        <html><head><style>.btn{background:url(https://cdn.x/bg.png)}</style>
        <title>Ignore me</title></head>
        <body><script>var t="https://tracker.example/pixel?id=99";</script>
        <p>Amount due 1840</p></body></html>''');
      expect(text, 'Amount due 1840');
    });

    test('tracking pixels and remote images leave nothing behind', () {
      final text = htmlToText(
          '<p>Hello</p><img src="https://track.example/open.gif?u=42" '
          'width="1" height="1"><p>Bye</p>');
      expect(text, isNot(contains('track.example')));
      expect(text, isNot(contains('img')));
      expect(text, 'Hello\nBye');
    });

    test('attribute values never survive as text', () {
      final text = htmlToText(
          '<div class="preheader mso-hide" data-id="x9">Shipped</div>');
      expect(text, 'Shipped');
    });

    test('a stray unclosed script does not eat the message', () {
      // The close-tag backreference is what bounds this; without it a quoted
      // "<script>" in a body of forwarded text would swallow the rest.
      expect(htmlToText('<p>Before</p><script>x=1<p>After</p>'),
          contains('Before'));
    });
  });

  group('entities', () {
    test('the rupee sign decodes from its numeric form', () {
      // Indian senders write &#8377; — left encoded, every currency pattern
      // in the extractors misses the amount entirely.
      expect(htmlToText('<p>Amount due &#8377;1,840.00</p>'),
          'Amount due ₹1,840.00');
      expect(decodeHtmlEntities('&#x20B9;500'), '₹500');
    });

    test('&amp; inside a URL survives as a single ampersand', () {
      expect(
        htmlToText('<a href="https://x.com/t?a=1&amp;b=2">Go</a>'),
        'Go https://x.com/t?a=1&b=2',
      );
    });

    test('decoding does not cascade into a second pass', () {
      // &amp;lt; is the literal text "&lt;", not a "<". A two-pass decoder
      // would turn escaped markup in a forwarded email back into markup.
      expect(decodeHtmlEntities('&amp;lt;b&amp;gt;'), '&lt;b&gt;');
    });

    test('nbsp becomes a real space so amounts tokenise', () {
      expect(htmlToText('<p>Total:&nbsp;&#8377;42,350</p>'),
          'Total: ₹42,350');
    });

    test('an unknown entity is left exactly as written', () {
      expect(decodeHtmlEntities('&notarealentity; &#99999999999;'),
          '&notarealentity; &#99999999999;');
    });
  });

  group('line structure', () {
    test('block tags become newlines so link context cannot smear', () {
      // extractActionUrl reads ±80 characters around a URL. Collapsed to one
      // line, an unsubscribe footer sitting near a button would lend it the
      // wrong words.
      expect(htmlToText('<p>One</p><p>Two</p><div>Three</div>'),
          'One\nTwo\nThree');
      expect(htmlToText('Line<br>Break'), 'Line\nBreak');
    });

    test('table cells stay on one line, rows do not', () {
      expect(
        htmlToText('<table><tr><td>Order</td><td>402-1234</td></tr>'
            '<tr><td>Total</td><td>1299</td></tr></table>'),
        'Order 402-1234\nTotal 1299',
      );
    });

    test('whitespace runs collapse and the result is trimmed', () {
      expect(htmlToText('  <p>   spaced     out   </p>  \n\n '), 'spaced out');
    });

    test('plain text with no markup passes through unharmed', () {
      expect(htmlToText('Amount due 1840 by 12 Aug 2026'),
          'Amount due 1840 by 12 Aug 2026');
    });
  });

  group('the extractor actually finds links it could not find before', () {
    EmailMeta emailWith(String body) => EmailMeta(
          id: 'm1',
          from: 'Amazon <ship@amazon.in>',
          subject: 'Your order has shipped',
          snippet: 'On the way.',
          body: body,
          date: DateTime(2026, 8, 1),
        );

    test('a real HTML shipping button resolves to the tracking URL', () {
      const html = '''
        <table><tr><td>
          <p>Your order has shipped and is on its way.</p>
          <a href="https://www.delhivery.com/track/package/AWB99"
             style="display:block">Track your package</a>
          <p style="font-size:10px">
            <a href="https://acme.com/unsubscribe?u=9">Unsubscribe</a> ·
            <a href="https://acme.com/privacy">Privacy</a>
          </p>
        </td></tr></table>''';
      final url = extractActionUrl(
        emailWith(htmlToText(html)),
        keywords: const ['track', 'shipment'],
        preferHosts: const ['delhivery.com'],
      );
      expect(url, 'https://www.delhivery.com/track/package/AWB99');
    });

    test('junk links are emitted here and rejected downstream', () {
      // Deliberate layering: the flattener reports every link the user could
      // have clicked and judges none of them. Choosing lives in
      // links.dart, which already scores and has a junk list — duplicating
      // that here would mean two places to keep in step, and a link this
      // file silently swallowed could never be recovered.
      const html =
          '<a href="https://acme.com/unsubscribe?u=9">Unsubscribe</a>'
          '<a href="https://www.delhivery.com/track/package/AWB99">Track</a>';
      final text = htmlToText(html);
      expect(text, contains('acme.com/unsubscribe'));

      expect(
        extractActionUrl(emailWith(text),
            keywords: const ['track'], preferHosts: const ['delhivery.com']),
        'https://www.delhivery.com/track/package/AWB99',
        reason: 'the scorer drops it, not the flattener',
      );
    });
  });
}
