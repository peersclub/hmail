/// HTML email → plain text the extractors can actually read.
///
/// WHY THIS EXISTS
/// Most transactional mail is `multipart/alternative` with an HTML part that
/// carries everything and a `text/plain` part that is either missing or a
/// "view this in your browser" stub. Reading only `text/plain` therefore hands
/// the extractors a couple of hundred characters of subject and snippet, with
/// none of the amounts, dates or call-to-action links that are the entire
/// point of a scan.
///
/// WHAT MAKES THIS DIFFERENT FROM STRIPPING TAGS
/// Anchors are flattened to `label href`, not dropped and not reduced to a
/// bare URL. `data/extractors/links.dart` scores a candidate URL by the action
/// language within ±80 characters of it, so the anchor's own wording — "Track
/// your order", "Pay now" — is the strongest possible signal, and it only
/// exists in the markup. Flattened this way, HTML is *better* input than
/// text/plain, not a degraded substitute.
///
/// WHAT IS DELIBERATELY THROWN AWAY
/// `<script>`, `<style>`, `<head>` and their contents: full of URLs and class
/// names that would land in [EmailMeta.haystack], where every extractor
/// pattern-matches. A tracking pixel's `<img src>` goes too — only `<a href>`
/// survives, so nothing is pulled out that the user could not have clicked.
///
/// Pure Dart: no plugins, no platform code, fully unit testable.
library;

/// Longest run of markup we will read. HTML emails routinely carry tens of
/// kilobytes of table scaffolding, and the flattened result is capped far
/// below this anyway — bounding the input keeps one pathological newsletter
/// from stalling a sync that has hundreds of messages to get through.
const _maxHtmlInput = 200000;

final _comment = RegExp(r'<!--[\s\S]*?-->');

/// Elements whose *contents* are not prose. The backreference keeps a stray
/// `<script>` in a body of quoted text from eating the rest of the message.
final _nonProse = RegExp(
  r'<(script|style|head|title|noscript)\b[^>]*>[\s\S]*?</\1\s*>',
  caseSensitive: false,
);

/// `<a href=…>label</a>` in all three quoting styles, label captured last.
final _anchor = RegExp(
  r'''<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)</a\s*>''',
  caseSensitive: false,
);

/// Tags that end a line of prose. Kept as newlines so the ±80-character
/// context window in [extractActionUrl] can't smear a footer's wording onto a
/// button that happened to render near it.
final _blockBoundary = RegExp(
  r'</?(?:p|div|br|tr|li|ul|ol|h[1-6]|table|thead|tbody|blockquote'
  r'|section|article|header|footer|hr)\b[^>]*>',
  caseSensitive: false,
);

final _anyTag = RegExp(r'<[^>]*>');

/// One pass over every `&…;`, so decoding can't cascade: `&amp;lt;` decodes to
/// the text `&lt;` and stops, rather than becoming a `<` that the tag stripper
/// has already run past.
final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]{1,31});');

const _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ensp': ' ',
  'emsp': ' ',
  'thinsp': ' ',
  'shy': '',
  'mdash': '—',
  'ndash': '–',
  'minus': '−',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'hellip': '…',
  'bull': '•',
  'middot': '·',
  'trade': '™',
  'copy': '©',
  'reg': '®',
  'deg': '°',
  'euro': '€',
  'pound': '£',
  'yen': '¥',
  'cent': '¢',
  'times': '×',
  'divide': '÷',
  'eacute': 'é',
  'egrave': 'è',
  'uuml': 'ü',
  'ouml': 'ö',
  'auml': 'ä',
  'ccedil': 'ç',
  'ntilde': 'ñ',
};

/// Decodes HTML entities, including the numeric forms.
///
/// Numeric matters more than it looks for this app's users: Indian merchants
/// write the rupee sign as `&#8377;`, so without this an amount reads as
/// "&#8377;1,840" and every currency pattern in the extractors misses it.
String decodeHtmlEntities(String text) =>
    text.replaceAllMapped(_entity, (match) {
      final body = match.group(1)!;
      if (!body.startsWith('#')) {
        return _namedEntities[body.toLowerCase()] ?? match.group(0)!;
      }
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(
        body.substring(hex ? 2 : 1),
        radix: hex ? 16 : 10,
      );
      // Control characters and out-of-range values stay as written rather
      // than becoming invisible junk in the middle of an amount.
      if (code == null || code < 9 || code > 0x10ffff) return match.group(0)!;
      if (code >= 0xd800 && code <= 0xdfff) return match.group(0)!;
      return String.fromCharCode(code == 160 ? 32 : code);
    });

/// Collapses runs of spaces without collapsing the line structure — the
/// newlines are load-bearing for link scoring.
String _collapse(String text) => text
    .replaceAll(RegExp(r'[ \t ​\r]+'), ' ')
    .replaceAll(RegExp(r' ?\n[ \n]*'), '\n')
    .trim();

/// Flattens an HTML email body to prose, with each link rendered as its own
/// label followed by its URL.
String htmlToText(String html) {
  var text = html.length > _maxHtmlInput
      ? html.substring(0, _maxHtmlInput)
      : html;

  text = text.replaceAll(_comment, ' ');
  text = text.replaceAll(_nonProse, ' ');

  text = text.replaceAllMapped(_anchor, (match) {
    final href = decodeHtmlEntities(
        (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim());
    final label = _collapse(
        decodeHtmlEntities(match.group(4)!.replaceAll(_anyTag, ' ')))
        .replaceAll('\n', ' ');
    // In-page jumps and `mailto:` are never the action we surface, but the
    // wording around them is still prose worth keeping.
    final keep = href.isNotEmpty &&
        !href.startsWith('#') &&
        !href.toLowerCase().startsWith('mailto:') &&
        !href.toLowerCase().startsWith('tel:') &&
        !href.toLowerCase().startsWith('javascript:');
    return keep ? ' $label $href ' : ' $label ';
  });

  text = text.replaceAll(_blockBoundary, '\n');
  text = text.replaceAll(_anyTag, ' ');
  return _collapse(decodeHtmlEntities(text));
}
