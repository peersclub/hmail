/// The teacher: turns unrecognised email shapes into playbook entries.
///
/// NoMail's rule extractors only understand the content types we hardcoded.
/// Everything else — an IRCTC e-ticket, a society maintenance demand, a school
/// fee circular — falls through as "unclaimed". This layer asks the model to
/// study those leftovers **once** and write a reusable [ContentType]: how to
/// recognise the shape, which fields to pull, what actions to offer. From then
/// on [Playbook] applies the entry deterministically — free, instant, offline —
/// and the model is never asked about that shape again.
///
/// ## Why learning is capped and pre-filtered
///
/// This runs on every sync, so the default has to be "spend nothing".
///
/// 1. **Already-known shapes never reach the model.** [Playbook.knows] is a
///    pure string test over matchers we already have; running it first means a
///    mailbox in steady state (every recurring sender already taught) sends
///    zero tokens per sync forever. Paying to relearn a shape is pure waste,
///    and re-learning a *disabled* entry would also silently undo a user's
///    deliberate choice — so disabled entries count as known too.
/// 2. **Only recurring, machine-sent clusters are candidates.** A one-off human
///    email has no reusable shape to learn; teaching the playbook from it costs
///    a request and yields an entry that will never match again.
/// 3. **`maxNewTypes` caps clusters per call** (hard-capped by
///    [KnowledgeLearner.maxClustersPerCall] regardless of what the caller
///    passes). Knowledge compounds: three good entries this sync means three
///    fewer clusters next sync. There is no reason to buy it all at once.
/// 4. **Bodies are truncated to [KnowledgeLearner.bodyExcerptChars].** Prompt
///    size is the cost driver, and the recognisable shape of a machine-sent
///    email lives in its first few hundred characters — the rest is footer,
///    legal boilerplate and unsubscribe links.
/// 5. **One request per call**, describing all clusters together, rather than
///    one request per cluster.
///
/// Like every AI surface in this app, the learner never throws. A failure
/// degrades to "no new knowledge", exactly as a failed [InsightAi.analyze]
/// degrades to the rule-based brief.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/ai_key.dart';

import '../../domain/knowledge.dart';
import '../../domain/models.dart';

/// Outcome of one learning pass. Immutable.
class LearnedTypes {
  /// Entries that survived [ContentType.validate] and every extra safety
  /// check. Safe to [Playbook.upsert] as-is.
  final List<ContentType> types;

  /// Human-readable `entry: reason` lines for everything rejected. Kept
  /// rather than discarded so a bad learner can be audited from the UI.
  final List<String> skipped;

  /// Set when the pass produced nothing for an operational reason (no key,
  /// network failure, unparseable reply). Never a thrown exception.
  final String? error;

  const LearnedTypes({
    this.types = const [],
    this.skipped = const [],
    this.error,
  });

  static const empty = LearnedTypes();

  bool get isEmpty => types.isEmpty;
  bool get hasError => error != null;

  @override
  String toString() =>
      'LearnedTypes(${types.map((t) => t.id).join(', ')}'
      '${skipped.isEmpty ? '' : ', skipped=${skipped.length}'}'
      '${error == null ? '' : ', error=$error'})';
}

/// A group of unclaimed emails from one sender domain — the unit of learning.
class _Cluster {
  final String domain;
  final List<EmailMeta> emails;

  _Cluster(this.domain, this.emails);

  /// Prompt-facing handle, so the model can say which cluster an entry is for.
  /// The sender domain itself: unique by construction, and self-describing in
  /// the prompt, which is one less thing for the model to get wrong.
  String get ref => domain;

  /// Every distinct sender domain in the cluster — what a learned matcher term
  /// has to be grounded in.
  Set<String> get domains => {for (final e in emails) e.senderDomain};
}

/// Asks the model to author playbook entries for email shapes nothing
/// recognises. See the library doc comment for the cost model.
class KnowledgeLearner {
  final Dio _dio;

  KnowledgeLearner({Dio? dio}) : _dio = dio ?? Dio();

  // Same endpoint, env var names and default model as OpenRouterAi: one key in
  // .env configures every AI surface in the app.
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _defaultModel = 'anthropic/claude-haiku-4.5';

  /// Body characters per sampled email sent to the model.
  static const bodyExcerptChars = 600;

  /// Emails sampled per cluster — three is enough to see what varies.
  static const samplesPerCluster = 3;

  /// Hard ceiling on clusters per request, whatever `maxNewTypes` asks for.
  static const maxClustersPerCall = 5;

  /// Unclaimed emails inspected per pass; bounds clustering work on a backfill.
  static const maxEmailsInspected = 400;

  /// A learned regex that captures more than this from a dense line of text is
  /// treated as a catch-all, not a field.
  static const maxProbeCaptureChars = 120;

  /// Schemes a learned action may open. `http` is excluded deliberately: a
  /// model-written payment link must not be downgradeable in transit.
  static const allowedSchemes = {'https', 'upi'};

  String? get _apiKey {
    final key = AiKey.value;
    return (key == null || key.isEmpty) ? null : key;
  }

  String get _model =>
      dotenv.maybeGet('OPENROUTER_MODEL')?.trim().isNotEmpty == true
          ? dotenv.maybeGet('OPENROUTER_MODEL')!.trim()
          : _defaultModel;

  bool get isConfigured => _apiKey != null;

  String get label => isConfigured ? 'Learner · $_model' : 'off';

  /// Studies [unclaimed] and returns playbook entries for the shapes worth
  /// teaching. Emails [known] already handles are dropped before anything is
  /// sent. Never throws.
  Future<LearnedTypes> learn({
    required List<EmailMeta> unclaimed,
    required Playbook known,
    int maxNewTypes = 3,
  }) async {
    try {
      if (maxNewTypes <= 0) {
        return const LearnedTypes(error: 'learning budget is zero');
      }

      // Cheapest filter first — a shape we were already taught costs nothing
      // to skip and a full request to relearn.
      final fresh = <EmailMeta>[];
      for (final email in unclaimed.take(maxEmailsInspected)) {
        if (email.senderDomain.isEmpty) continue;
        if (known.knows(email)) continue;
        fresh.add(email);
      }
      if (fresh.isEmpty) return LearnedTypes.empty;

      final clusters = _clusters(fresh, maxNewTypes);
      if (clusters.isEmpty) return LearnedTypes.empty;

      // Only spend the key check once we know there is something to buy.
      final key = _apiKey;
      if (key == null) {
        return const LearnedTypes(error: 'No OpenRouter key — add one in Settings → AI');
      }

      final content = await _post(key, _prompt(clusters));
      if (content == null) {
        return const LearnedTypes(error: 'no content in model response');
      }

      final raw = _parseEntries(content);
      if (raw == null) {
        return const LearnedTypes(error: 'model reply was not valid JSON');
      }

      return _accept(raw, clusters, known, maxNewTypes);
    } catch (e) {
      // A broken learner degrades to "no new knowledge", never to a failed
      // sync.
      return LearnedTypes(error: _describe(e));
    }
  }

  // ---------------------------------------------------------------- clustering

  /// Words that mark a machine-generated transaction rather than a human note
  /// or a campaign.
  static const _transactionalWords = [
    'order', 'invoice', 'receipt', 'booking', 'booked', 'ticket', 'pnr',
    'shipped', 'dispatched', 'out for delivery', 'tracking', 'consignment',
    'awb', 'due', 'amount payable', 'payment', 'paid', 'statement', 'bill',
    'renewal', 'subscription', 'appointment', 'reservation', 'confirmation',
    'confirmed', 'reference number', 'transaction', 'e-ticket', 'boarding',
    'refund', 'policy number', 'premium', 'installment', 'emi',
  ];

  /// Campaign language. Present without any transactional word, the cluster is
  /// newsletter noise and not worth a token.
  static const _marketingWords = [
    'sale', '% off', 'discount', 'deal', 'offer ends', 'newsletter',
    'webinar', 'flash sale', 'limited time', 'shop now', 'coupon',
    'exclusive', 'introducing', 'blog', 'digest', 'weekly roundup',
  ];

  /// Local-parts that only automated senders use.
  static const _machineSenders = [
    'noreply', 'no-reply', 'no_reply', 'donotreply', 'do-not-reply',
    'do_not_reply', 'notification', 'notifications', 'alerts', 'alert',
    'updates', 'mailer', 'automated', 'auto', 'service', 'services',
    'support', 'billing', 'bills', 'statements', 'tickets', 'booking',
    'orders', 'info', 'care', 'txn', 'transaction',
  ];

  static int _transactionalScore(EmailMeta email) {
    final hay = email.haystack;
    return _transactionalWords.where(hay.contains).length;
  }

  static bool _looksMachineSent(EmailMeta email) {
    final from = email.from.toLowerCase();
    final local = from.contains('@') ? from.split('@').first : from;
    if (_machineSenders.any(local.contains)) return true;
    final hay = email.haystack;
    return hay.contains('do not reply') ||
        hay.contains('this is an automated') ||
        hay.contains('unsubscribe');
  }

  static bool _looksMarketing(EmailMeta email) =>
      _marketingWords.any(email.haystack.contains) &&
      _transactionalScore(email) == 0;

  /// Groups by sender domain, keeps the clusters that look like a recurring
  /// machine-sent shape, and returns the best [limit] of them.
  ///
  /// A cluster of two or more from one domain is already evidence of a
  /// repeating shape, so it only has to look automated. A lone email has no
  /// such evidence and must be unmistakably transactional to earn a request.
  List<_Cluster> _clusters(List<EmailMeta> emails, int limit) {
    final byDomain = <String, List<EmailMeta>>{};
    for (final email in emails) {
      byDomain.putIfAbsent(email.senderDomain, () => []).add(email);
    }

    final worth = <_Cluster>[];
    for (final entry in byDomain.entries) {
      final cluster = _Cluster(entry.key, entry.value);
      if (_worthLearning(cluster)) worth.add(cluster);
    }

    worth.sort((a, b) {
      final bySize = b.emails.length.compareTo(a.emails.length);
      if (bySize != 0) return bySize;
      final byScore = _clusterScore(b).compareTo(_clusterScore(a));
      if (byScore != 0) return byScore;
      return a.domain.compareTo(b.domain); // deterministic tie-break
    });

    final cap = limit.clamp(1, maxClustersPerCall);
    return worth.take(cap).toList();
  }

  static int _clusterScore(_Cluster cluster) =>
      cluster.emails.map(_transactionalScore).fold(0, (a, b) => a + b);

  static bool _worthLearning(_Cluster cluster) {
    if (cluster.domain.isEmpty) return false;
    if (cluster.emails.every(_looksMarketing)) return false;

    if (cluster.emails.length > 1) {
      // Recurrence is the signal; it just has to be automated, not human.
      return cluster.emails.any(_looksMachineSent) ||
          cluster.emails.any((e) => _transactionalScore(e) > 0);
    }

    final only = cluster.emails.first;
    final score = _transactionalScore(only);
    return score >= 2 || (score >= 1 && _looksMachineSent(only));
  }

  // -------------------------------------------------------------------- prompt

  static String _excerpt(String text, int limit) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
  }

  String _prompt(List<_Cluster> clusters) {
    final buffer = StringBuffer();
    for (final cluster in clusters) {
      buffer.writeln('--- cluster "${cluster.ref}" '
          '(${cluster.emails.length} email(s)) ---');
      for (final email in cluster.emails.take(samplesPerCluster)) {
        buffer.writeln('from: ${email.from}');
        buffer.writeln('subject: ${email.subject}');
        buffer.writeln(
            'body: ${_excerpt('${email.snippet} ${email.body}', bodyExcerptChars)}');
        buffer.writeln();
      }
    }

    return '''
You are teaching an email app to recognise content types it has never seen.
Below are clusters of emails, grouped by sender domain, that no existing rule
understands. For each cluster that is a genuine recurring machine-generated
document, write ONE reusable playbook entry: how to recognise this shape, which
fields to pull out, and what the user can do with them. The app applies your
entry deterministically to future emails and will never ask you about this
shape again, so it must be exact.

The app ships rules for only a handful of document types — receipts, bills,
shipments, invites, tickets. Everything else in a real mailbox is your job:
school fees, insurance renewals, society maintenance, EMI reminders, visa and
passport appointments, medical appointments, tax deadlines, utility connections,
government notices, gym and club memberships, salary slips, exam schedules.
Those are the entries worth writing, because nothing else in the app will ever
handle them.

$buffer
Rules — an entry breaking any of these is discarded:
1. "match.senderDomains" is REQUIRED and must contain a fragment of the actual
   sender domain of that cluster. Never invent a brand domain that is not in
   the cluster. The matcher must be impossible to trigger from an unrelated
   sender; add "subjectAny" words that this document type always carries.
2. Every field "pattern" is a regex with EXACTLY ONE capture group around the
   value itself. No ".*"/".+" catch-alls: match the real token shape
   (\\b([A-Z]{2}\\d{9}IN)\\b, ([0-9]{10}), ₹\\s?([0-9][0-9,]*\\.?[0-9]{0,2})).
   Use "nearKeyword" when the value is only identifiable by the label printed
   before it ("PNR", "Amount Due", "Tracking Number").
3. Every "uriTemplate" must be a real, working destination for THIS brand — the
   carrier's tracking page that accepts the tracking number, the biller's own
   payment page, the operator's booking-lookup page. It must start with
   https:// or upi:// (never http://, javascript:, mailto: or a bare path), and
   every {placeholder} in it must be the "name" of a field you declared above.
   If you do not know a real URL for this brand, omit the action entirely
   rather than guessing a domain.
4. "produces" is exactly one of: delivery, bill, subscription, event, generic.
   Pick the specific one when the document genuinely is that thing. Otherwise
   pick "generic" — it is a first-class outcome, not a failure: the app renders
   generic entries as their own cards with their own name, amount and deadline.
   Do NOT force a school fee demand, an insurance renewal, a visa appointment,
   a society maintenance notice, an EMI reminder, a tax deadline or a medical
   appointment into "bill" or "event" because they are nearest. A wrongly typed
   entry is worse than a generic one.
5. For a "generic" entry, two field names are load-bearing, so use these exact
   names whenever the document contains them:
     - "amount"  — the money owed or paid
     - "dueDate" — when it must be done by
   The app reads those two names to show a figure and a deadline, and to rank
   the card. A generic entry with neither is still accepted, but it can only
   ever be a name and a link, so it will sit near the bottom of the list.
6. "id" is a lowercase slug (letters, digits, dot, dash, underscore), e.g.
   "irctc-eticket". Put the single most useful field first in "fields".
7. "label" is what the user will read on the card, so name the DOCUMENT, not the
   sender: "School fee demand", "Policy renewal", "Maintenance bill" — not
   "Notification from ABC Schools". Two to four words, sentence case.
8. If a cluster is marketing, a newsletter, a one-off human email, or anything
   with no stable extractable value, SKIP IT. Returning fewer entries — or an
   empty list — is always better than guessing.

Set "cluster" to the exact quoted cluster name it describes.

Return ONLY JSON, no prose, no code fence. Two entries shown: a typed one and
a generic one, which is the more common case.
{"types": [{
  "cluster": "irctc.co.in",
  "id": "irctc-eticket",
  "label": "IRCTC e-ticket",
  "match": {"senderDomains": ["irctc.co.in"], "subjectAny": ["ticket"],
            "bodyAll": []},
  "produces": "event",
  "fields": [{"name": "pnr", "pattern": "\\\\b([0-9]{10})\\\\b",
              "nearKeyword": "PNR"}],
  "actions": [{"label": "Check PNR status",
               "uriTemplate": "https://www.irctc.co.in/online-charts/pnr/{pnr}",
               "kind": "openLink"}]
}, {
  "cluster": "greenwoodhigh.edu.in",
  "id": "greenwood-fee-demand",
  "label": "School fee demand",
  "match": {"senderDomains": ["greenwoodhigh.edu.in"],
            "subjectAny": ["fee"], "bodyAll": []},
  "produces": "generic",
  "fields": [{"name": "amount",
              "pattern": "\u20b9\\s?([0-9][0-9,]*\\.?[0-9]{0,2})",
              "nearKeyword": "Total payable"},
             {"name": "dueDate",
              "pattern": "([0-9]{1,2}\\s+[A-Za-z]{3,9}\\s+[0-9]{4})",
              "nearKeyword": "last date"}],
  "actions": []
}]}
''';
  }

  // --------------------------------------------------------------- transport

  /// Compact OpenRouter chat call. Returns the assistant text, or null when the
  /// response is shaped unexpectedly.
  Future<String?> _post(String key, String prompt) async {
    final response = await _dio.post(
      _endpoint,
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
        'HTTP-Referer': 'https://github.com/peersclub/hmail',
        'X-Title': 'NoMail',
      }),
      data: {
        'model': _model,
        'max_tokens': 2000,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      },
    );

    final data = response.data;
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  static String _stripFences(String text) {
    var out = text.trim();
    if (out.startsWith('```')) {
      out = out.replaceFirst(RegExp(r'^```[a-z]*\s*'), '');
      if (out.endsWith('```')) out = out.substring(0, out.length - 3);
    }
    return out.trim();
  }

  /// Accepts `{"types": [...]}` or a bare array; null when neither decodes.
  static List<Map<String, dynamic>>? _parseEntries(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(_stripFences(content));
    } catch (_) {
      return null;
    }
    final list = decoded is List
        ? decoded
        : (decoded is Map ? decoded['types'] : null);
    if (list is! List) return null;
    return [
      for (final entry in list)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  // ----------------------------------------------------------------- vetting

  /// Validates, grounds and stamps provenance on each candidate entry.
  LearnedTypes _accept(
    List<Map<String, dynamic>> raw,
    List<_Cluster> clusters,
    Playbook known,
    int maxNewTypes,
  ) {
    final byRef = {for (final c in clusters) c.ref: c};
    final accepted = <ContentType>[];
    final skipped = <String>[];
    final seenIds = <String>{};
    final now = DateTime.now();

    for (final entry in raw) {
      final label = (entry['id'] ?? entry['label'] ?? '<unnamed>').toString();

      if (accepted.length >= maxNewTypes) {
        skipped.add('$label: over the $maxNewTypes-entry budget for this pass');
        continue;
      }

      // Which cluster is this about? A single-cluster call can be forgiving;
      // otherwise a missing/unknown ref means we cannot ground anything.
      final ref = entry['cluster'];
      final cluster = ref is String ? byRef[ref] : null;
      final target =
          cluster ?? (clusters.length == 1 ? clusters.first : null);
      if (target == null) {
        skipped.add('$label: names unknown cluster "$ref"');
        continue;
      }

      final ContentType candidate;
      try {
        candidate = ContentType.fromJson(entry).copyWith(
          learnedFromEmailId: target.emails.first.id,
          learnedAt: now,
          learnedByModel: _model,
          matchCount: 0,
          correctionCount: 0,
          enabled: true,
        );
      } catch (e) {
        skipped.add('$label: could not be decoded (${_describe(e)})');
        continue;
      }

      final problems = <String>[
        ...candidate.validate(),
        ..._extraProblems(candidate, target, known, seenIds),
      ];
      if (problems.isNotEmpty) {
        skipped.add('${candidate.id.isEmpty ? label : candidate.id}: '
            '${problems.join('; ')}');
        continue;
      }

      seenIds.add(candidate.id);
      accepted.add(candidate);
    }

    return LearnedTypes(types: accepted, skipped: skipped);
  }

  /// Safety checks beyond [ContentType.validate] — everything that needs the
  /// originating cluster, the existing playbook, or a runtime probe.
  List<String> _extraProblems(
    ContentType type,
    _Cluster cluster,
    Playbook known,
    Set<String> seenIds,
  ) {
    final problems = <String>[];

    // 1. Duplicate ids: within this batch, and against what we already know.
    if (seenIds.contains(type.id)) {
      problems.add('duplicate id in this batch');
    }
    if (known.byId(type.id) != null) {
      problems.add('id already exists in the playbook');
    }

    // 2. Sender-domain scoping. A subject-only matcher would fire on any
    //    sender that happens to use the same word.
    if (type.match.senderDomains.isEmpty) {
      problems.add('matcher has no sender domain, so it is not brand-scoped');
    }

    // 3. Grounding: every claimed domain must really occur in this cluster,
    //    tested exactly the way ContentMatcher tests it. This is what stops a
    //    model hallucinating 'amazon.in' from an unrelated sender.
    final actual = cluster.domains;
    for (final term in type.match.senderDomains) {
      if (!actual.any((d) => d.contains(term))) {
        problems.add('sender domain "$term" does not appear in cluster '
            '${actual.join(', ')}');
      }
    }

    // 4. End-to-end grounding: the finished matcher must claim at least one of
    //    the emails it was written from. Catches invented subject/body terms.
    if (!cluster.emails.any(type.match.matches)) {
      problems.add('matcher does not match any email it was learned from');
    }

    // 5. Schemes. validate() only blocks javascript:/data:/vbscript:/file:;
    //    a learned action may only ever open https or upi.
    for (final action in type.actions) {
      final uri = Uri.tryParse(action.uriTemplate.replaceAll(
          RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}'), 'x'));
      final scheme = uri?.scheme.toLowerCase() ?? '';
      if (!allowedSchemes.contains(scheme)) {
        problems.add('action "${action.label}" uses '
            '"${scheme.isEmpty ? action.uriTemplate : '$scheme:'}" — only '
            '${allowedSchemes.join('/')} are allowed');
      }
    }

    // 6. Regexes: must compile and must not behave as a catch-all.
    for (final rule in type.fields) {
      final why = _regexProblem(rule.pattern);
      if (why != null) problems.add('field "${rule.name}" $why');
    }

    // 7. An entry that extracts nothing and does nothing is not knowledge.
    if (type.fields.isEmpty && type.actions.isEmpty) {
      problems.add('entry has no fields and no actions');
    }

    return problems;
  }

  /// Degenerate catch-alls, spelled out so the probe is not the only defence.
  static const _catchAlls = {
    r'(.*)', r'(.+)', r'(.*?)', r'(.+?)', r'([\s\S]*)', r'([\s\S]+)',
    r'(\w*)', r'(\W*)', r'(\S*)', r'([^]*)',
  };

  /// A dense, newline-free line: a greedy `.*` swallows all of it, while a
  /// well-shaped token pattern captures only its token.
  static final String _probe = ('Order #AB-123456 PNR 4512345678 Tracking '
              'Number 1Z999AA10123456784 Amount Due Rs. 1,840.50 payable by '
              '15 Aug 2026 ref TXN00099887766 policy 55/AB/9921 for your '
              'shipment from the warehouse in Bengaluru India ' *
          4)
      .trim();

  /// Why [pattern] is unusable as a field rule, or null when it is fine.
  static String? _regexProblem(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return 'has an empty pattern';
    if (trimmed.length > ContentType.maxPatternLength) {
      return 'pattern is longer than ${ContentType.maxPatternLength} characters';
    }
    if (_catchAlls.contains(trimmed.replaceAll(' ', ''))) {
      return 'is a catch-all pattern that would capture the whole email';
    }

    final RegExp regex;
    try {
      regex = RegExp(trimmed, caseSensitive: false);
    } catch (e) {
      return 'has a regex that does not compile (${_describe(e)})';
    }

    try {
      final match = regex.firstMatch(_probe);
      if (match != null) {
        final captured =
            (match.groupCount >= 1 ? match.group(1) : match.group(0)) ?? '';
        if (captured.length > maxProbeCaptureChars) {
          return 'captures ${captured.length} characters of ordinary text — '
              'too broad to be a field';
        }
      }
    } catch (e) {
      // Backreferences and lookbehind can throw at match time.
      return 'throws while matching (${_describe(e)})';
    }
    return null;
  }

  static String _describe(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status != null
          ? 'HTTP $status from OpenRouter'
          : 'network error: ${error.type.name}';
    }
    final text = error.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}
