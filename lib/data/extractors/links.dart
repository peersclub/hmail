/// Link extraction — turns email text into actionable URLs.
///
/// Every insight should carry the link that acts on it: the tracking page for
/// a shipment, the pay page (or upi:// intent) for a bill, the join link for
/// a meeting. Marketing emails bury these among banner and footer links, so
/// candidates are scored by adjacency to action language instead of taking
/// the first URL that appears.
library;

import '../../domain/models.dart';

final _urlPattern = RegExp(
  r'''(upi://pay\?[^\s<>"'\)\]]+|https?://[^\s<>"'\)\]]+)''',
);

/// Links that are never the action the user wants.
const _junkFragments = [
  'unsubscribe',
  'email-preferences',
  'preferences',
  'privacy',
  '/terms',
  'facebook.com',
  'twitter.com',
  'x.com/',
  'instagram.com',
  'youtube.com',
  'play.google.com',
  'apps.apple.com',
];

String _stripTrailingPunctuation(String url) =>
    url.replaceAll(RegExp(r'[.,;:!?\)\]>]+$'), '');

/// The URL in [email] most likely to be the action link for [keywords]:
/// scored by action language in the URL itself or within ±80 chars of it,
/// with a bonus for [preferHosts] fragments (carrier domains, /pay paths).
/// Returns null below a confidence floor — a wrong deep link is worse than
/// falling back to opening the source email.
String? extractActionUrl(
  EmailMeta email, {
  required List<String> keywords,
  List<String> preferHosts = const [],
}) {
  final raw = email.rawText;
  final lower = raw.toLowerCase();

  String? best;
  var bestScore = 0;
  for (final match in _urlPattern.allMatches(raw)) {
    final url = _stripTrailingPunctuation(match.group(0)!);
    final urlLower = url.toLowerCase();
    if (url.length < 12 || _junkFragments.any(urlLower.contains)) continue;

    var score = 1;
    if (url.startsWith('upi://')) score += 10;
    if (preferHosts.any(urlLower.contains)) score += 8;
    if (keywords.any(urlLower.contains)) score += 4;
    final contextStart = (match.start - 80).clamp(0, lower.length);
    final contextEnd = (match.end + 40).clamp(0, lower.length);
    final context = lower.substring(contextStart, contextEnd);
    if (keywords.any(context.contains)) score += 6;

    if (score > bestScore) {
      bestScore = score;
      best = url;
    }
  }
  // Score 1 means "a URL exists but nothing ties it to the action" — reject.
  return bestScore >= 5 ? best : null;
}

final _meetingPatterns = <MeetingProvider, RegExp>{
  MeetingProvider.meet: RegExp(r'https://meet\.google\.com/[a-z][a-z-]{5,}'),
  MeetingProvider.zoom:
      RegExp(r"""https://[\w.-]*zoom\.us/j/[^\s<>"'\)\]]+"""),
  MeetingProvider.teams: RegExp(
      r"""https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"'\)\]]+"""),
  MeetingProvider.webex:
      RegExp(r"""https://[\w.-]*webex\.com/(?:meet|join|wbxmjs)[^\s<>"'\)\]]*"""),
};

/// First video-conference link in [rawText], with its provider.
({String url, MeetingProvider provider})? extractMeetingLink(String rawText) {
  for (final entry in _meetingPatterns.entries) {
    final match = entry.value.firstMatch(rawText);
    if (match != null) {
      return (
        url: _stripTrailingPunctuation(match.group(0)!),
        provider: entry.key,
      );
    }
  }
  return null;
}
