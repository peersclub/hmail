/// Price-hike detection — the pay trigger.
///
/// "Netflix went ₹649 → ₹699" is the one insight no free inbox gives you, and
/// the app already has both halves of it: last sync's stored subscriptions and
/// this sync's fresh ones. All that is missing is the diff, which is what this
/// file is.
///
/// Timing matters. `InsightStore.merge` collapses subscriptions by service
/// (`Subscription.dedupeKey` is the lowercased name), so the moment a snapshot
/// is merged the old amount is gone. [detectPriceChanges] therefore runs on
/// the *pre-merge* pair, and deliberately reuses merge's own collapse rule
/// (latest `lastSeen` wins) so the "new" price it reports is always the same
/// number the Money tab will render.
library;

import 'models.dart';

/// A price move must clear both floors to count: a relative one so a currency
/// with big nominal values (₹) isn't noisier than a small one, and an absolute
/// one so float drift on a cheap plan can never register.
const _minRelativeDelta = 0.01; // 1%
const _minAbsoluteDelta = 0.01; // one minor unit

/// Diffs [previous] against [fresh] and returns the genuine price moves.
///
/// Every guard here kills a specific class of false hike:
///
///  * **same service, currency and cadence** — ₹649/mo against $8.99/mo, or a
///    monthly plan against the same plan billed yearly, are different products
///    priced differently, not a change;
///  * **different source email** — re-reading one email after an extractor fix
///    changes the amount without the merchant changing anything;
///  * **newer evidence only** — the new amount has to come from later mail
///    than the old one, otherwise a backfilled old receipt reads as a hike;
///  * **both floors above** — rounding and tax-inclusive/exclusive wobble.
///
/// Pure: [now] defaults to the wall clock but is injectable, so the whole
/// detector is testable with a frozen one.
List<PriceChange> detectPriceChanges({
  required List<Subscription> previous,
  required List<Subscription> fresh,
  DateTime? now,
}) {
  if (previous.isEmpty || fresh.isEmpty) return const [];
  final detectedAt = now ?? DateTime.now();

  final before = _collapse(previous);
  final after = _collapse(fresh);

  final changes = <PriceChange>[];
  for (final entry in after.entries) {
    final old = before[entry.key];
    if (old == null) continue; // brand new subscription, not a change
    final current = entry.value;

    if (old.currency != current.currency) continue;
    if (old.cadence != current.cadence) continue;
    if (old.sourceEmailId == current.sourceEmailId) continue;
    if (!current.lastSeen.isAfter(old.lastSeen)) continue;
    if (!_isMeaningful(old.amount, current.amount)) continue;

    changes.add(PriceChange(
      service: current.service,
      oldAmount: old.amount,
      newAmount: current.amount,
      currency: current.currency,
      cadence: current.cadence,
      detectedAt: detectedAt,
      sourceEmailId: current.sourceEmailId,
    ));
  }

  // Biggest monthly impact first — the same order the snapshot getter uses,
  // so a truncated list always shows the changes that matter most.
  changes.sort((a, b) => b.monthlyDelta.abs().compareTo(a.monthlyDelta.abs()));
  return changes;
}

/// One entry per service, keeping the most recently seen — `InsightStore.merge`
/// does exactly this, and the detector has to agree with it.
Map<String, Subscription> _collapse(List<Subscription> subs) {
  final map = <String, Subscription>{};
  for (final sub in subs) {
    final existing = map[sub.dedupeKey];
    if (existing == null || sub.lastSeen.isAfter(existing.lastSeen)) {
      map[sub.dedupeKey] = sub;
    }
  }
  return map;
}

bool _isMeaningful(double oldAmount, double newAmount) {
  final delta = (newAmount - oldAmount).abs();
  if (delta < _minAbsoluteDelta) return false;
  // A zero or negative old amount can't be a base for a percentage, and it
  // means extraction failed rather than the price changing.
  if (oldAmount <= 0) return false;
  return delta / oldAmount >= _minRelativeDelta;
}

/// Merges detected changes into the stored history: one entry per
/// `dedupeKey` (service + new amount), stale ones dropped.
///
/// Kept out of `InsightStore.merge` because a price change is derived from a
/// snapshot pair rather than extracted from mail — the store merges what the
/// pipeline produced, and this is what produces it.
List<PriceChange> mergePriceChanges(
  List<PriceChange> stored,
  List<PriceChange> detected,
) {
  final map = <String, PriceChange>{
    for (final change in stored)
      if (!change.isStale) change.dedupeKey: change,
  };
  for (final change in detected) {
    final existing = map[change.dedupeKey];
    if (existing == null || change.detectedAt.isAfter(existing.detectedAt)) {
      map[change.dedupeKey] = change;
    }
  }
  final all = map.values.toList()
    ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  return all;
}

/// Monthly money the app has caught moving, by currency and signed: positive
/// is what subscriptions quietly added, negative what fell.
///
/// Grouped by currency because summing ₹ and $ into one figure would be a
/// lie, and this number's whole job is to be trusted.
Map<String, double> priceDriftByCurrency(List<PriceChange> changes) {
  final totals = <String, double>{};
  for (final change in changes) {
    totals[change.currency] =
        (totals[change.currency] ?? 0) + change.monthlyDelta;
  }
  return totals;
}
