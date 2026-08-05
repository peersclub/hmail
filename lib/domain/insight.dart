import 'package:flutter/cupertino.dart';

import 'actions.dart';
import 'ignore_list.dart';

/// The eight durable top-level domains an inbox generates. New insight types
/// slot into one of these — the domain drives Timeline's filter chips and the
/// ranker's baseline weighting, so adding a type never touches navigation.
enum InsightDomain {
  security('Security', CupertinoIcons.lock_shield),
  money('Money', CupertinoIcons.creditcard),
  commerce('Deliveries', CupertinoIcons.cube_box),
  travel('Travel', CupertinoIcons.airplane),
  work('Work', CupertinoIcons.calendar),
  content('Reads', CupertinoIcons.book),
  personal('Personal', CupertinoIcons.person_crop_circle),
  government('Identity', CupertinoIcons.doc_text);

  const InsightDomain(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// How much time pressure an insight carries. Drives both the Today ordering
/// and which tier ("Needs attention" / "Coming up" / "Recent") it renders in.
enum UrgencyTier { imminent, near, ambient }

/// A type-agnostic view of any insight. Concrete models (Bill, Delivery, …)
/// are wrapped into this by `snapshotToInsights`; every screen renders through
/// it, so the UI never switches on concrete type.
class Insight {
  final String id;
  final InsightDomain domain;
  final String title;
  final String? subtitle;

  /// Right-aligned value (an amount, an ETA day) — optional.
  final String? trailing;

  /// Small caption under the trailing value ("Due tomorrow", "Renews 31 Aug").
  final String? caption;

  /// When this insight matters — due date, ETA, event start, publish date.
  /// Null means timeless (informational).
  final DateTime? anchorDate;

  /// Past its deadline (bills only, today). Drives the red urgency treatment.
  final bool overdue;

  /// Category or brand glyph. Brand resolution happens at the call site via
  /// [brandKey]; this is the fallback.
  final IconData icon;

  /// Service/merchant/source name for brand-logo resolution (may be null).
  final String? brandKey;

  /// Per-item importance within a tier (overdue bill > renewing sub). Higher
  /// sorts first. Baselined from the domain, adjusted by the mapper.
  final int weight;

  final List<InsightAction> actions;

  /// What a "this isn't a bill" correction on this row would suppress, and for
  /// which name. Null means the row offers no correction — either because the
  /// family has no useful generalisation, or because there is no name to
  /// generalise on. [ignoreSubject] falls back to [brandKey].
  final IgnoreKind? ignoreKind;
  final String? ignoreSubject;

  const Insight({
    required this.id,
    required this.domain,
    required this.title,
    this.subtitle,
    this.trailing,
    this.caption,
    this.anchorDate,
    this.overdue = false,
    required this.icon,
    this.brandKey,
    required this.weight,
    this.actions = const [],
    this.ignoreKind,
    this.ignoreSubject,
  });

  /// The name a correction would apply to, or null when there isn't one.
  String? get correctionSubject {
    if (ignoreKind == null) return null;
    final subject = (ignoreSubject ?? brandKey)?.trim();
    return (subject == null || subject.isEmpty) ? null : subject;
  }

  UrgencyTier get urgency {
    if (overdue) return UrgencyTier.imminent;
    final date = anchorDate;
    if (date == null) return UrgencyTier.ambient;
    final hours = date.difference(DateTime.now()).inHours;
    if (hours < 0) {
      // A past anchor that isn't an overdue bill (a meeting that started, a
      // delivery ETA gone by) is no longer pressing.
      return UrgencyTier.ambient;
    }
    if (hours < 6) return UrgencyTier.imminent;
    if (hours <= 72) return UrgencyTier.near;
    return UrgencyTier.ambient;
  }
}

/// Ranks heterogeneous insights into one ordering: urgency tier first, then
/// per-item weight, then soonest anchor. Deterministic and cheap — recomputed
/// at render time, never persisted.
List<Insight> rankInsights(List<Insight> insights) {
  int tierRank(UrgencyTier t) => switch (t) {
        UrgencyTier.imminent => 3,
        UrgencyTier.near => 2,
        UrgencyTier.ambient => 1,
      };

  final sorted = [...insights];
  sorted.sort((a, b) {
    final tier = tierRank(b.urgency).compareTo(tierRank(a.urgency));
    if (tier != 0) return tier;
    final w = b.weight.compareTo(a.weight);
    if (w != 0) return w;
    // Soonest anchor first; null anchors last.
    final ad = a.anchorDate, bd = b.anchorDate;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  });
  return sorted;
}
