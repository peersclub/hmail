/// The playbook — learned content types.
///
/// Every content type NoMail understands today is hardcoded in
/// `data/extractors/`. That works for the shapes we anticipated and fails
/// silently for everything else: an IRCTC e-ticket, a society maintenance
/// demand, a school fee circular. The playbook generalises those hand-written
/// rules into data.
///
/// When the AI meets an email shape nobody has taught the app, it authors a
/// [ContentType] describing how to recognise and read that shape. From then on
/// the entry is applied deterministically — free, instant, offline, testable —
/// and the model is never asked about that shape again.
///
/// **These entries are written by a language model, so every surface here is
/// paranoid.** A malformed regex yields null instead of throwing, a matcher
/// with no anchoring constraint matches nothing rather than the whole inbox,
/// a template with a missing field produces no action rather than a URL with a
/// literal `{trackingNumber}` in it, and [ContentType.validate] lets the
/// learner reject a bad entry at the boundary instead of persisting it.
///
/// Pure Dart — no Flutter imports — so it is testable in isolation.
library;

import 'models.dart';

/// Compiled-regex cache. [FieldRule] is const-constructible and immutable, so
/// the compiled form lives here rather than on the instance; patterns are few
/// (a handful per learned type) and shared across every email in a scan.
final Map<String, RegExp?> _regexCache = {};

/// Above this the cache is dropped wholesale — a runaway learner cannot grow
/// it without bound.
const _maxRegexCacheEntries = 256;

RegExp? _compile(String pattern) {
  if (pattern.isEmpty || pattern.length > ContentType.maxPatternLength) {
    return null;
  }
  if (_regexCache.containsKey(pattern)) return _regexCache[pattern];
  if (_regexCache.length >= _maxRegexCacheEntries) _regexCache.clear();
  RegExp? compiled;
  try {
    // Case-insensitive by default: a model writes `PNR` or `pnr` from one
    // sample email and the next one differs. Matching should not be a coin
    // flip on the sample it happened to learn from.
    compiled = RegExp(pattern, caseSensitive: false);
  } catch (_) {
    compiled = null;
  }
  _regexCache[pattern] = compiled;
  return compiled;
}

List<String> _lowerList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();
}

String _stringOr(dynamic value, String fallback) =>
    value is String ? value : fallback;

/// How a playbook entry recognises an email.
///
/// Mirrors what the hand-written extractors do: key off a sender-domain
/// fragment, confirm with subject words, optionally require body evidence.
class ContentMatcher {
  /// Any-of, substring-tested against [EmailMeta.senderDomain]
  /// ('irctc' matches 'ticketadmin.irctc.co.in').
  final List<String> senderDomains;

  /// Any-of, lowercase substring against the subject.
  final List<String> subjectAny;

  /// All-of, lowercase substring against [EmailMeta.haystack]. May be empty.
  final List<String> bodyAll;

  const ContentMatcher({
    this.senderDomains = const [],
    this.subjectAny = const [],
    this.bodyAll = const [],
  });

  /// A sender fragment shorter than this is treated as unsafe — 'in' would
  /// match most of the inbox.
  static const minTermLength = 3;

  /// An entry with neither a sender domain nor a subject term has nothing
  /// anchoring it to a real content shape. Body-only matching is how a learned
  /// entry swallows an entire inbox, so it is refused outright rather than
  /// merely discouraged.
  bool get isAnchored => senderDomains.isNotEmpty || subjectAny.isNotEmpty;

  bool matches(EmailMeta email) {
    if (!isAnchored) return false;

    if (senderDomains.isNotEmpty) {
      final domain = email.senderDomain;
      if (!senderDomains.any(domain.contains)) return false;
    }
    if (subjectAny.isNotEmpty) {
      final subject = email.subject.toLowerCase();
      if (!subjectAny.any(subject.contains)) return false;
    }
    if (bodyAll.isNotEmpty) {
      final hay = email.haystack;
      if (!bodyAll.every(hay.contains)) return false;
    }
    return true;
  }

  /// Ranking score when several entries claim the same email — more and longer
  /// constraints win. All-of body terms weigh most (they are the hardest to
  /// satisfy), then sender domains, then any-of subject words.
  int get specificity {
    var score = 0;
    for (final domain in senderDomains) {
      score += 4 + domain.length;
    }
    for (final term in subjectAny) {
      score += 2 + term.length;
    }
    for (final term in bodyAll) {
      score += 6 + term.length;
    }
    return score;
  }

  ContentMatcher copyWith({
    List<String>? senderDomains,
    List<String>? subjectAny,
    List<String>? bodyAll,
  }) =>
      ContentMatcher(
        senderDomains: senderDomains ?? this.senderDomains,
        subjectAny: subjectAny ?? this.subjectAny,
        bodyAll: bodyAll ?? this.bodyAll,
      );

  Map<String, dynamic> toJson() => {
        'senderDomains': senderDomains,
        'subjectAny': subjectAny,
        'bodyAll': bodyAll,
      };

  /// Tolerant: anything that is not a list of strings becomes empty, and every
  /// term is normalised to lowercase so matching never depends on how the
  /// model happened to capitalise it.
  factory ContentMatcher.fromJson(Map<String, dynamic> json) => ContentMatcher(
        senderDomains: _lowerList(json['senderDomains']),
        subjectAny: _lowerList(json['subjectAny']),
        bodyAll: _lowerList(json['bodyAll']),
      );

  @override
  String toString() => 'ContentMatcher(${toJson()})';
}

/// One extracted value: a named regex, optionally anchored near a keyword.
class FieldRule {
  /// Placeholder name used by [ActionTemplate.uriTemplate], e.g. 'pnr'.
  final String name;

  /// Regex with exactly one capture group; the group is the value.
  final String pattern;

  /// When set, only the ~120 characters following the first occurrence of this
  /// keyword are searched. This is what stops a tracking-number pattern from
  /// grabbing an order ID elsewhere in the body — the same windowing the
  /// hand-written delivery extractor does around the word 'tracking'.
  final String? nearKeyword;

  const FieldRule({
    required this.name,
    required this.pattern,
    this.nearKeyword,
  });

  static const windowLength = 120;

  /// The value, or null. Never throws: a pattern that does not compile, a
  /// keyword that is not present, and no match all return null alike.
  String? extract(EmailMeta email) {
    final regex = _compile(pattern);
    if (regex == null) return null;

    // Original case: links and reference codes carry case-sensitive tokens
    // that haystack's lowercasing would corrupt. The regex is
    // case-insensitive, so nothing is lost by searching the raw text.
    final text = email.rawText;
    var haystack = text;

    final keyword = nearKeyword;
    if (keyword != null && keyword.isNotEmpty) {
      final index = text.toLowerCase().indexOf(keyword.toLowerCase());
      if (index < 0) return null;
      final end = (index + windowLength).clamp(0, text.length);
      haystack = text.substring(index, end);
    }

    try {
      final match = regex.firstMatch(haystack);
      if (match == null) return null;
      final value =
          (match.groupCount >= 1 ? match.group(1) : match.group(0))?.trim();
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      // Backreference/lookbehind edge cases can throw at match time even
      // though the pattern compiled.
      return null;
    }
  }

  /// True when [pattern] compiles and captures exactly one group — what the
  /// learner must guarantee.
  bool get isWellFormed =>
      _compile(pattern) != null && _captureCount(pattern) == 1;

  FieldRule copyWith({String? name, String? pattern, String? nearKeyword}) =>
      FieldRule(
        name: name ?? this.name,
        pattern: pattern ?? this.pattern,
        nearKeyword: nearKeyword ?? this.nearKeyword,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'pattern': pattern,
        'nearKeyword': nearKeyword,
      };

  factory FieldRule.fromJson(Map<String, dynamic> json) => FieldRule(
        name: _stringOr(json['name'], '').trim(),
        pattern: _stringOr(json['pattern'], ''),
        nearKeyword: json['nearKeyword'] is String &&
                (json['nearKeyword'] as String).trim().isNotEmpty
            ? (json['nearKeyword'] as String).trim()
            : null,
      );

  @override
  String toString() => 'FieldRule(${toJson()})';
}

/// Counts capturing groups in [pattern]: an unescaped `(` outside a character
/// class that is either plain or a named group `(?<name>`. `(?:`, `(?=`, `(?!`
/// and the lookbehinds `(?<=` / `(?<!` do not capture.
int _captureCount(String pattern) {
  var count = 0;
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\') {
      i++;
      continue;
    }
    if (inClass) {
      if (char == ']') inClass = false;
      continue;
    }
    if (char == '[') {
      inClass = true;
      continue;
    }
    if (char != '(') continue;

    final next = i + 1 < pattern.length ? pattern[i + 1] : '';
    if (next != '?') {
      count++;
      continue;
    }
    // `(?<name>` captures; `(?<=` and `(?<!` are lookbehinds.
    final after = i + 2 < pattern.length ? pattern[i + 2] : '';
    final named = i + 3 < pattern.length ? pattern[i + 3] : '';
    if (after == '<' && named != '=' && named != '!') count++;
  }
  return count;
}

/// A tappable action built from extracted fields.
class ActionTemplate {
  final String label;

  /// URI with `{fieldName}` placeholders, e.g.
  /// `https://www.irctc.co.in/pnr/{pnr}`.
  final String uriTemplate;

  /// Free-form intent tag ('track', 'pay', 'openLink', 'addToCalendar') that
  /// the app maps onto its own action enum. Deliberately a string: the model
  /// must not be constrained by, or able to break, our enum.
  final String kind;

  const ActionTemplate({
    required this.label,
    required this.uriTemplate,
    this.kind = 'openLink',
  });

  static final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

  /// Schemes a learned template may never produce.
  static const blockedSchemes = {'javascript', 'data', 'vbscript', 'file'};

  static const maxTemplateLength = 400;

  /// Field names this template needs, in order of appearance.
  List<String> get placeholders => _placeholder
      .allMatches(uriTemplate)
      .map((m) => m.group(1)!)
      .toSet()
      .toList();

  /// Substitutes [fields], URL-encoding each value, and returns null when any
  /// referenced field is missing or empty — a half-built URL carrying a
  /// literal `{pnr}` is worse than no button at all.
  Uri? build(Map<String, String> fields) {
    if (uriTemplate.isEmpty || uriTemplate.length > maxTemplateLength) {
      return null;
    }
    var out = uriTemplate;
    for (final name in placeholders) {
      final value = fields[name];
      if (value == null || value.trim().isEmpty) return null;
      out = out.replaceAll('{$name}', Uri.encodeComponent(value.trim()));
    }
    // A leftover brace means a malformed placeholder we could not resolve.
    if (out.contains('{') || out.contains('}')) return null;

    final uri = Uri.tryParse(out);
    if (uri == null || !uri.hasScheme) return null;
    if (blockedSchemes.contains(uri.scheme.toLowerCase())) return null;
    return uri;
  }

  ActionTemplate copyWith({String? label, String? uriTemplate, String? kind}) =>
      ActionTemplate(
        label: label ?? this.label,
        uriTemplate: uriTemplate ?? this.uriTemplate,
        kind: kind ?? this.kind,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'uriTemplate': uriTemplate,
        'kind': kind,
      };

  factory ActionTemplate.fromJson(Map<String, dynamic> json) => ActionTemplate(
        label: _stringOr(json['label'], '').trim(),
        uriTemplate: _stringOr(json['uriTemplate'], '').trim(),
        kind: _stringOr(json['kind'], 'openLink').trim().isEmpty
            ? 'openLink'
            : _stringOr(json['kind'], 'openLink').trim(),
      );

  @override
  String toString() => 'ActionTemplate(${toJson()})';
}

/// Which existing insight lane a learned type feeds. `generic` means "none of
/// the above" — the entry stands on its own in the UI.
enum ProducesKind { delivery, bill, subscription, event, generic }

ProducesKind _producesFrom(dynamic value) => ProducesKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => ProducesKind.generic,
    );

/// One playbook entry: everything the app needs to handle a content shape it
/// was taught rather than born knowing.
class ContentType {
  /// Stable slug — the upsert key. e.g. 'irctc-eticket'.
  final String id;

  /// Human label shown in the UI, e.g. 'IRCTC e-ticket'.
  final String label;

  final ContentMatcher match;
  final ProducesKind produces;
  final List<FieldRule> fields;
  final List<ActionTemplate> actions;

  /// Provenance — which email taught us this, when, and by which model. Kept
  /// so a bad entry can be traced back to its source and the learner audited.
  final String learnedFromEmailId;
  final DateTime learnedAt;
  final String? learnedByModel;

  /// How often this entry has claimed an email, and how often the user
  /// corrected it. A high correction ratio is the signal to retire an entry.
  final int matchCount;
  final int correctionCount;

  /// The user can switch an entry off without deleting it — a disabled entry
  /// stops matching but still counts as "known", so the AI does not pay to
  /// relearn something that was deliberately turned off.
  final bool enabled;

  const ContentType({
    required this.id,
    required this.label,
    required this.match,
    this.produces = ProducesKind.generic,
    this.fields = const [],
    this.actions = const [],
    this.learnedFromEmailId = '',
    required this.learnedAt,
    this.learnedByModel,
    this.matchCount = 0,
    this.correctionCount = 0,
    this.enabled = true,
  });

  static const maxFields = 12;
  static const maxActions = 6;
  static const maxPatternLength = 300;
  static const maxLabelLength = 80;

  /// Slug shape for [id]: lowercase, no whitespace.
  static final _slug = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

  /// Rules and actions actually executed, hard-capped regardless of what the
  /// model wrote. [validate] reports the overflow; the engine simply refuses
  /// to run past the cap.
  List<FieldRule> get effectiveFields =>
      fields.length <= maxFields ? fields : fields.sublist(0, maxFields);

  List<ActionTemplate> get effectiveActions =>
      actions.length <= maxActions ? actions : actions.sublist(0, maxActions);

  /// Everything wrong with this entry — empty means it is safe to persist.
  /// The learner calls this at the boundary and drops anything non-empty, so
  /// a malformed entry never reaches storage in the first place.
  List<String> validate() {
    final problems = <String>[];

    if (id.trim().isEmpty) {
      problems.add('id is empty');
    } else if (!_slug.hasMatch(id)) {
      problems.add('id "$id" is not a lowercase slug');
    }

    if (label.trim().isEmpty) {
      problems.add('label is empty');
    } else if (label.length > maxLabelLength) {
      problems.add('label is longer than $maxLabelLength characters');
    }

    if (!match.isAnchored) {
      problems.add(
          'matcher is over-broad: needs at least one sender domain or subject term');
    }
    for (final term in [...match.senderDomains, ...match.subjectAny]) {
      if (term.length < ContentMatcher.minTermLength) {
        problems.add('matcher term "$term" is too short to be safe');
      }
    }

    if (fields.length > maxFields) {
      problems.add('too many fields (${fields.length} > $maxFields)');
    }
    if (actions.length > maxActions) {
      problems.add('too many actions (${actions.length} > $maxActions)');
    }

    final names = <String>{};
    for (final rule in fields) {
      if (rule.name.trim().isEmpty) {
        problems.add('field with empty name');
        continue;
      }
      if (!names.add(rule.name)) {
        problems.add('duplicate field name "${rule.name}"');
      }
      if (_compile(rule.pattern) == null) {
        problems.add('field "${rule.name}" has an invalid regex');
      } else if (_captureCount(rule.pattern) != 1) {
        problems.add(
            'field "${rule.name}" must have exactly one capture group');
      }
    }

    for (final action in actions) {
      if (action.label.trim().isEmpty) {
        problems.add('action with empty label');
      }
      final unknown =
          action.placeholders.where((p) => !names.contains(p)).toList();
      if (unknown.isNotEmpty) {
        problems.add(
            'action "${action.label}" references unknown field(s) ${unknown.join(', ')}');
      }
      // Probe the template with placeholder values: catches a missing scheme,
      // an unparseable URI, and a blocked scheme without needing a real email.
      final probe = {for (final name in action.placeholders) name: 'x'};
      if (action.build(probe) == null) {
        problems.add('action "${action.label}" has a malformed uriTemplate');
      }
    }

    return problems;
  }

  bool get isValid => validate().isEmpty;

  ContentType copyWith({
    String? id,
    String? label,
    ContentMatcher? match,
    ProducesKind? produces,
    List<FieldRule>? fields,
    List<ActionTemplate>? actions,
    String? learnedFromEmailId,
    DateTime? learnedAt,
    String? learnedByModel,
    int? matchCount,
    int? correctionCount,
    bool? enabled,
  }) =>
      ContentType(
        id: id ?? this.id,
        label: label ?? this.label,
        match: match ?? this.match,
        produces: produces ?? this.produces,
        fields: fields ?? this.fields,
        actions: actions ?? this.actions,
        learnedFromEmailId: learnedFromEmailId ?? this.learnedFromEmailId,
        learnedAt: learnedAt ?? this.learnedAt,
        learnedByModel: learnedByModel ?? this.learnedByModel,
        matchCount: matchCount ?? this.matchCount,
        correctionCount: correctionCount ?? this.correctionCount,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'match': match.toJson(),
        'produces': produces.name,
        'fields': fields.map((f) => f.toJson()).toList(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'learnedFromEmailId': learnedFromEmailId,
        'learnedAt': learnedAt.toIso8601String(),
        'learnedByModel': learnedByModel,
        'matchCount': matchCount,
        'correctionCount': correctionCount,
        'enabled': enabled,
      };

  /// Tolerant in both directions: entries written by an older build must keep
  /// loading, and entries written by a model must not be able to crash the
  /// decoder. Anything unreadable falls back to a harmless default.
  factory ContentType.fromJson(Map<String, dynamic> json) {
    List<T> mapList<T>(dynamic value, T Function(Map<String, dynamic>) from) {
      if (value is! List) return const [];
      final out = <T>[];
      for (final entry in value) {
        if (entry is! Map) continue;
        try {
          out.add(from(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // Skip the bad entry, keep the good ones.
        }
      }
      return out;
    }

    DateTime learnedAt;
    try {
      learnedAt = DateTime.parse(json['learnedAt'] as String);
    } catch (_) {
      learnedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return ContentType(
      id: _stringOr(json['id'], '').trim(),
      label: _stringOr(json['label'], '').trim(),
      match: json['match'] is Map
          ? ContentMatcher.fromJson(
              Map<String, dynamic>.from(json['match'] as Map))
          : const ContentMatcher(),
      produces: _producesFrom(json['produces']),
      fields: mapList(json['fields'], FieldRule.fromJson),
      actions: mapList(json['actions'], ActionTemplate.fromJson),
      learnedFromEmailId: _stringOr(json['learnedFromEmailId'], ''),
      learnedAt: learnedAt,
      learnedByModel:
          json['learnedByModel'] is String ? json['learnedByModel'] as String : null,
      matchCount: json['matchCount'] is num ? (json['matchCount'] as num).toInt() : 0,
      correctionCount: json['correctionCount'] is num
          ? (json['correctionCount'] as num).toInt()
          : 0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }

  @override
  String toString() => 'ContentType($id)';
}

/// One resolved action, ready for the UI to render as a button.
typedef BuiltAction = ({String label, Uri uri, String kind});

/// The result of applying a playbook entry to an email.
class KnowledgeMatch {
  final ContentType type;

  /// Field name → extracted value. Rules that found nothing are absent.
  final Map<String, String> fields;

  /// Actions whose fields were all present. Actions missing a field are
  /// dropped rather than rendered broken.
  final List<BuiltAction> actions;

  const KnowledgeMatch({
    required this.type,
    required this.fields,
    required this.actions,
  });

  /// The first rule (declaration order) that produced a value — the learner is
  /// told to put the most useful field first.
  String? get primaryFieldName {
    for (final rule in type.effectiveFields) {
      if (fields.containsKey(rule.name)) return rule.name;
    }
    return null;
  }

  String? get primaryValue {
    final name = primaryFieldName;
    return name == null ? null : fields[name];
  }

  String get title => type.label;

  /// 'Pnr: 4512345678' — the entry's most useful extracted value, or null when
  /// nothing was extracted.
  String? get subtitle {
    final name = primaryFieldName;
    if (name == null) return null;
    return '${_humanize(name)}: ${fields[name]}';
  }

  static String _humanize(String name) {
    final spaced = name
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)!.toLowerCase()}')
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return name;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  String toString() => 'KnowledgeMatch(${type.id}, $fields)';
}

/// The playbook: the set of learned content types, and the deterministic
/// engine that applies them. Immutable — mutations return a new instance.
class Playbook {
  final List<ContentType> types;

  const Playbook({this.types = const []});

  static const empty = Playbook();

  bool get isEmpty => types.isEmpty;
  int get length => types.length;

  ContentType? byId(String id) {
    for (final type in types) {
      if (type.id == id) return type;
    }
    return null;
  }

  /// Enabled entries that claim [email], most specific first. Ties break on id
  /// so the result never depends on insertion order.
  List<ContentType> candidatesFor(EmailMeta email) {
    final hits = types
        .where((t) => t.enabled && t.match.matches(email))
        .toList()
      ..sort((a, b) {
        final bySpecificity =
            b.match.specificity.compareTo(a.match.specificity);
        return bySpecificity != 0 ? bySpecificity : a.id.compareTo(b.id);
      });
    return hits;
  }

  /// Applies the best matching enabled entry, or null when nothing claims the
  /// email. Never throws: bad regexes and bad templates degrade to missing
  /// fields and missing buttons.
  KnowledgeMatch? apply(EmailMeta email) {
    final candidates = candidatesFor(email);
    if (candidates.isEmpty) return null;
    final type = candidates.first;

    final fields = <String, String>{};
    for (final rule in type.effectiveFields) {
      if (rule.name.trim().isEmpty || fields.containsKey(rule.name)) continue;
      final value = rule.extract(email);
      if (value != null) fields[rule.name] = value;
    }

    final actions = <BuiltAction>[];
    for (final template in type.effectiveActions) {
      final uri = template.build(fields);
      if (uri == null) continue;
      final label = template.label.trim();
      if (label.isEmpty) continue;
      actions.add((label: label, uri: uri, kind: template.kind));
    }

    return KnowledgeMatch(type: type, fields: fields, actions: actions);
  }

  /// Splits [emails] into those a learned entry claimed and those still
  /// unclaimed — the unclaimed list is exactly what the AI learner looks at.
  ({List<KnowledgeMatch> matched, List<EmailMeta> unclaimed}) applyAll(
      List<EmailMeta> emails) {
    final matched = <KnowledgeMatch>[];
    final unclaimed = <EmailMeta>[];
    for (final email in emails) {
      final hit = apply(email);
      if (hit == null) {
        unclaimed.add(email);
      } else {
        matched.add(hit);
      }
    }
    return (matched: matched, unclaimed: unclaimed);
  }

  /// Cheap "have I already been taught this shape?" — the check the AI layer
  /// runs before spending a token. Disabled entries count as known: the user
  /// turned that entry off deliberately and relearning it would undo them.
  bool knows(EmailMeta email) => types.any((t) => t.match.matches(email));

  /// Replaces the entry with the same id, or appends. Order of existing
  /// entries is preserved so the settings list does not jump around on edit.
  Playbook upsert(ContentType type) {
    final next = <ContentType>[];
    var replaced = false;
    for (final existing in types) {
      if (existing.id == type.id) {
        next.add(type);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(type);
    return Playbook(types: next);
  }

  Playbook remove(String id) =>
      Playbook(types: types.where((t) => t.id != id).toList());

  Playbook setEnabled(String id, bool enabled) => Playbook(
        types: types
            .map((t) => t.id == id ? t.copyWith(enabled: enabled) : t)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'types': types.map((t) => t.toJson()).toList(),
      };

  /// Skips any entry that fails to decode rather than losing the whole
  /// playbook to one bad record.
  factory Playbook.fromJson(Map<String, dynamic> json) {
    final raw = json['types'];
    if (raw is! List) return const Playbook();
    final types = <ContentType>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        types.add(ContentType.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // Drop the bad entry, keep the rest.
      }
    }
    return Playbook(types: types);
  }

  @override
  String toString() => 'Playbook(${types.map((t) => t.id).join(', ')})';
}
