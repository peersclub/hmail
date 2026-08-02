/// Did the link actually work?
///
/// NoMail opens links whose native app isn't installed inside its own WebView
/// rather than handing them to Safari. Staying in the app is not the point —
/// it is what makes the point possible: we can ask one question ("did this
/// open the right page?") and keep the answer.
///
/// That answer is the only ground truth we have about URLs the app *guessed*.
/// Tracking and payment URLs are frequently assembled from a learned recipe —
/// a knowledge type template like `https://courier.example/track?awb={id}` —
/// and a template that drifts produces pages that load fine and are useless.
/// HTTP status can't see that; a human can. So every answer is tagged with the
/// recipe that produced the URL, and [LinkFeedbackLog.isSuspect] turns a
/// handful of thumbs-down into a signal that a recipe should be retired.
library;

/// What the user told us about the page that opened.
enum LinkOutcome {
  /// Right page. The recipe that built this URL is doing its job.
  worked,

  /// It loaded, but it was the wrong thing — a homepage, a search box, a
  /// "not found" page rendered with HTTP 200. The classic bad-template smell.
  wrongPage,

  /// It didn't load at all: DNS failure, dead host, main-frame error.
  brokenLink,

  /// The user left without answering. Recorded so an unanswered prompt is
  /// distinguishable from one that was never shown.
  dismissed,

  /// The page demanded a sign-in. A WKWebView carries none of Safari's
  /// cookies, so an auth-gated page renders logged-out here even when the
  /// URL is perfectly correct — indistinguishable, to the user, from a wrong
  /// page. Recorded for visibility but deliberately **not** counted as
  /// evidence: letting login walls accuse a recipe would retire good
  /// templates on the strength of a browser limitation.
  loginWall;

  /// Tolerant parse — an outcome written by a future build (or a corrupted
  /// entry) must not poison the whole log, so unknown names fall back to
  /// [dismissed], the outcome that asserts the least.
  static LinkOutcome parse(Object? raw) {
    if (raw is LinkOutcome) return raw;
    if (raw is String) {
      for (final value in LinkOutcome.values) {
        if (value.name == raw) return value;
      }
    }
    return LinkOutcome.dismissed;
  }

  /// Evidence against the URL. [worked] obviously isn't; neither is
  /// [loginWall], which says more about our WebView than about the link.
  bool get isFailure =>
      this != LinkOutcome.worked && this != LinkOutcome.loginWall;
}

/// One answer about one URL.
class LinkFeedback {
  final String url;

  /// The insight whose action opened this link, when there was one.
  final String? insightId;

  /// The email the insight came from — lets us re-read the source when a
  /// recipe turns out to be wrong.
  final String? sourceEmailId;

  /// The learned recipe that produced the URL, when it wasn't literal. This is
  /// the field that makes the log actionable rather than merely interesting.
  final String? knowledgeTypeId;

  final LinkOutcome outcome;
  final DateTime at;

  const LinkFeedback({
    required this.url,
    required this.outcome,
    required this.at,
    this.insightId,
    this.sourceEmailId,
    this.knowledgeTypeId,
  });

  LinkFeedback copyWith({
    String? url,
    String? insightId,
    String? sourceEmailId,
    String? knowledgeTypeId,
    LinkOutcome? outcome,
    DateTime? at,
  }) =>
      LinkFeedback(
        url: url ?? this.url,
        insightId: insightId ?? this.insightId,
        sourceEmailId: sourceEmailId ?? this.sourceEmailId,
        knowledgeTypeId: knowledgeTypeId ?? this.knowledgeTypeId,
        outcome: outcome ?? this.outcome,
        at: at ?? this.at,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (insightId != null) 'insightId': insightId,
        if (sourceEmailId != null) 'sourceEmailId': sourceEmailId,
        if (knowledgeTypeId != null) 'knowledgeTypeId': knowledgeTypeId,
        'outcome': outcome.name,
        'at': at.toIso8601String(),
      };

  /// Never throws. A single unreadable entry in a persisted log would
  /// otherwise cost us the whole history.
  factory LinkFeedback.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return LinkFeedback(
      url: str('url') ?? '',
      insightId: str('insightId'),
      sourceEmailId: str('sourceEmailId'),
      knowledgeTypeId: str('knowledgeTypeId'),
      outcome: LinkOutcome.parse(json['outcome']),
      at: DateTime.tryParse(str('at') ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LinkFeedback &&
      other.url == url &&
      other.insightId == insightId &&
      other.sourceEmailId == sourceEmailId &&
      other.knowledgeTypeId == knowledgeTypeId &&
      other.outcome == outcome &&
      other.at == at;

  @override
  int get hashCode =>
      Object.hash(url, insightId, sourceEmailId, knowledgeTypeId, outcome, at);

  @override
  String toString() => 'LinkFeedback(${toJson()})';
}

/// Immutable, bounded log of answers, oldest first.
class LinkFeedbackLog {
  /// Newest [maxEntries] are kept. This log is diagnostic, not an audit trail:
  /// old answers describe recipes that have since changed, and an unbounded
  /// list in SharedPreferences is a slow leak we'd never notice.
  static const int maxEntries = 200;

  final List<LinkFeedback> entries;

  const LinkFeedbackLog({this.entries = const []});

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  int get length => entries.length;

  /// Appends [feedback] and drops the oldest entries past the cap.
  LinkFeedbackLog add(LinkFeedback feedback) {
    final next = [...entries, feedback];
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }
    return LinkFeedbackLog(entries: next);
  }

  List<LinkFeedback> forUrl(String url) =>
      entries.where((e) => e.url == url).toList();

  List<LinkFeedback> forKnowledgeType(String id) =>
      entries.where((e) => e.knowledgeTypeId == id).toList();

  /// Answers for [knowledgeTypeId] that were anything other than "worked" —
  /// including `dismissed`, because a user who walks away from a page they
  /// expected to be a tracking page usually walked away for a reason.
  int failuresFor(String knowledgeTypeId) =>
      forKnowledgeType(knowledgeTypeId).where((e) => e.outcome.isFailure).length;

  /// A recipe worth reviewing: at least two failures and never once a
  /// success. One failure is noise (offline, a merchant outage); a recipe that
  /// works *sometimes* is a data problem for one email, not a bad template.
  bool isSuspect(String knowledgeTypeId) {
    final relevant = forKnowledgeType(knowledgeTypeId);
    if (relevant.any((e) => e.outcome == LinkOutcome.worked)) return false;
    return relevant.where((e) => e.outcome.isFailure).length >= 2;
  }

  /// Every knowledge type currently flagged by [isSuspect].
  List<String> get suspectKnowledgeTypes {
    final ids = <String>{
      for (final e in entries)
        if (e.knowledgeTypeId != null) e.knowledgeTypeId!,
    };
    return ids.where(isSuspect).toList();
  }

  Map<String, dynamic> toJson() => {
        'entries': [for (final e in entries) e.toJson()],
      };

  factory LinkFeedbackLog.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    if (raw is! List) return const LinkFeedbackLog();
    final parsed = <LinkFeedback>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          parsed.add(LinkFeedback.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip the bad entry, keep the rest.
        }
      }
    }
    if (parsed.length > maxEntries) {
      parsed.removeRange(0, parsed.length - maxEntries);
    }
    return LinkFeedbackLog(entries: parsed);
  }

  @override
  String toString() => 'LinkFeedbackLog(${entries.length} entries)';
}
