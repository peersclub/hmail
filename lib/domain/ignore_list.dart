/// "This isn't a bill" — corrections, kept on the device.
///
/// Extraction is heuristic, so it will always be wrong about something. The AI
/// audit catches a lot of it, but the audit is optional, costs money, and is
/// itself a guess. The user is the only source of ground truth in the app, and
/// until now a wrong insight could only be looked at, not corrected.
///
/// An ignore is deliberately *not* keyed to one email. "GitHub is not a
/// delivery" has to keep being true next week, when GitHub sends another
/// release note — so a rule is (kind, subject), where subject is the
/// merchant/issuer/service name the extractor derived from the sender. That is
/// exactly the granularity a user means when they tap the button, and it needs
/// no new plumbing: the name is already on every model.
///
/// Filtering happens on the way *out* of the store, never on the way in. The
/// snapshot keeps the ignored insight, so undoing a correction restores it
/// instantly instead of waiting for the email to be re-scanned — and a rule
/// the user later regrets costs them nothing.
library;

import 'models.dart';

/// The insight families a correction can apply to.
///
/// One per model rather than one per screen: the point of a rule is that it
/// survives, and screens change more often than models do.
enum IgnoreKind {
  subscription('subscription'),
  bill('bill'),
  delivery('package'),
  event('meeting'),
  travel('trip'),
  payment('payment alert'),
  returnItem('return'),
  feed('read'),
  attention('alert');

  const IgnoreKind(this.noun);

  /// How the user hears it: "Not a package".
  final String noun;

  static IgnoreKind? parse(Object? raw) {
    if (raw is IgnoreKind) return raw;
    if (raw is String) {
      for (final value in IgnoreKind.values) {
        if (value.name == raw) return value;
      }
    }
    return null;
  }
}

/// One correction: this kind of insight, from this name, is not wanted.
class IgnoreRule {
  final IgnoreKind kind;

  /// The merchant/issuer/service name, lowercased and trimmed. Matching is
  /// exact on this: a substring rule would let "Amazon" silence "Amazon Pay".
  final String subject;

  final DateTime at;

  IgnoreRule({
    required this.kind,
    required String subject,
    required this.at,
  }) : subject = subject.trim().toLowerCase();

  String get key => '${kind.name}|$subject';

  /// What the Settings row says: "Packages from github".
  String get label => '${_plural(kind)} from $subject';

  static String _plural(IgnoreKind kind) => switch (kind) {
        IgnoreKind.subscription => 'Subscriptions',
        IgnoreKind.bill => 'Bills',
        IgnoreKind.delivery => 'Packages',
        IgnoreKind.event => 'Meetings',
        IgnoreKind.travel => 'Trips',
        IgnoreKind.payment => 'Payment alerts',
        IgnoreKind.returnItem => 'Returns',
        IgnoreKind.feed => 'Reads',
        IgnoreKind.attention => 'Alerts',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'subject': subject,
        'at': at.toIso8601String(),
      };

  /// Null for an entry this build can't understand, so one bad rule never
  /// costs the user the rest of their corrections.
  static IgnoreRule? fromJson(Map<String, dynamic> json) {
    final kind = IgnoreKind.parse(json['kind']);
    final subject = json['subject'];
    if (kind == null || subject is! String || subject.trim().isEmpty) {
      return null;
    }
    return IgnoreRule(
      kind: kind,
      subject: subject,
      at: DateTime.tryParse(json['at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) => other is IgnoreRule && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The device's set of corrections, newest first.
class IgnoreList {
  final List<IgnoreRule> rules;

  const IgnoreList({this.rules = const []});

  static const IgnoreList empty = IgnoreList();

  bool get isEmpty => rules.isEmpty;
  int get length => rules.length;

  bool hides(IgnoreKind kind, String subject) {
    final needle = subject.trim().toLowerCase();
    return rules.any((r) => r.kind == kind && r.subject == needle);
  }

  /// Adding the same correction twice is a no-op rather than a duplicate row.
  IgnoreList add(IgnoreRule rule) {
    if (hides(rule.kind, rule.subject)) return this;
    return IgnoreList(rules: [rule, ...rules]);
  }

  IgnoreList remove(String key) =>
      IgnoreList(rules: [for (final r in rules) if (r.key != key) r]);

  Map<String, dynamic> toJson() => {
        'rules': [for (final r in rules) r.toJson()],
      };

  factory IgnoreList.fromJson(Map<String, dynamic> json) {
    final raw = json['rules'];
    if (raw is! List) return empty;
    final parsed = <IgnoreRule>[];
    for (final item in raw) {
      if (item is Map) {
        final rule = IgnoreRule.fromJson(Map<String, dynamic>.from(item));
        if (rule != null) parsed.add(rule);
      }
    }
    return IgnoreList(rules: parsed);
  }
}

/// The snapshot with every corrected insight filtered out.
///
/// Pure, and applied at read time — see the library note on why the store
/// keeps the raw data. Price changes ride along with their subscription: a
/// service the user says isn't a subscription can't have had a price rise.
InsightSnapshot applyIgnores(InsightSnapshot snapshot, IgnoreList ignores) {
  if (ignores.isEmpty) return snapshot;
  bool keep(IgnoreKind kind, String subject) => !ignores.hides(kind, subject);

  return snapshot.copyWith(
    subscriptions: [
      for (final s in snapshot.subscriptions)
        if (keep(IgnoreKind.subscription, s.service)) s,
    ],
    bills: [
      for (final b in snapshot.bills)
        if (keep(IgnoreKind.bill, b.issuer)) b,
    ],
    deliveries: [
      for (final d in snapshot.deliveries)
        if (keep(IgnoreKind.delivery, d.merchant)) d,
    ],
    events: [
      for (final e in snapshot.events)
        if (keep(IgnoreKind.event, e.organizer ?? e.title)) e,
    ],
    travel: [
      for (final t in snapshot.travel)
        if (keep(IgnoreKind.travel, t.provider)) t,
    ],
    payments: [
      for (final p in snapshot.payments)
        if (keep(IgnoreKind.payment, p.source)) p,
    ],
    returns: [
      for (final r in snapshot.returns)
        if (keep(IgnoreKind.returnItem, r.merchant)) r,
    ],
    feed: [
      for (final f in snapshot.feed)
        if (keep(IgnoreKind.feed, f.source)) f,
    ],
    attention: [
      for (final a in snapshot.attention)
        if (keep(IgnoreKind.attention, a.title)) a,
    ],
    priceChanges: [
      for (final c in snapshot.priceChanges)
        if (keep(IgnoreKind.subscription, c.service)) c,
    ],
  );
}
