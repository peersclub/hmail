import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/account_scope.dart';
import '../../domain/models.dart';
import '../../domain/price_watch.dart';

/// Local-first persistence: the last snapshot renders instantly on launch;
/// sync refreshes it in place — and it survives a sign-out.
///
/// The stored record is the snapshot *plus* the ordered account list it was
/// built against. That pairing is what makes surviving a sign-out safe: on the
/// way back in, the stored list is compared against whoever is signed in now,
/// so the same person gets their insights back, a different person gets
/// nothing, and a changed set of accounts gets the overlap with its indices
/// corrected. See `domain/account_scope.dart` for why indices need correcting.
class InsightStore {
  // Bump when extraction logic changes materially — forces a clean re-extract
  // instead of merging against stale results.
  static const _key = 'insight_snapshot_v11';

  /// Earlier keys held a bare snapshot with no account list. Read once on
  /// upgrade so nobody loses their history to a schema change, then written
  /// forward under [_key] on the next save.
  ///
  /// v10 is included even though it bumped for an extraction change: that bump
  /// was about wanting a re-extract, and a re-extract is exactly what the next
  /// sync does. Discarding the file as well would have blanked the app for
  /// everyone mid-upgrade, which is a worse trade than merging onto slightly
  /// stale rows for one cycle.
  static const _legacyKeys = ['insight_snapshot_v10', 'insight_snapshot_v9'];

  /// The snapshot, reconciled against [accounts] — the emails of the accounts
  /// signed in right now, in order.
  ///
  /// Null means "nothing to show": nothing stored, or a snapshot belonging to
  /// an account that is not signed in. A scoped snapshot with an empty
  /// [accounts] is also null, which is what keeps the signed-out screen from
  /// rendering the last user's data.
  Future<InsightSnapshot?> load({List<String> accounts = const []}) async =>
      (await loadScoped(accounts: accounts))?.snapshot;

  /// [load] plus what reconciliation had to do, for callers that report it.
  Future<({InsightSnapshot snapshot, ScopeVerdict verdict})?> loadScoped({
    List<String> accounts = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key);
    for (final legacy in _legacyKeys) {
      if (raw != null) break;
      raw = prefs.getString(legacy);
    }
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // A current record wraps the snapshot; a legacy one *is* the snapshot.
      final wrapped = decoded['snapshot'] is Map<String, dynamic>;
      final saved = wrapped
          ? [
              for (final e in (decoded['accounts'] as List? ?? const []))
                if (e is String) e,
            ]
          : const <String>[];
      final body =
          wrapped ? decoded['snapshot'] as Map<String, dynamic> : decoded;

      // Signed out, or mid-boot before auth resumed. A scoped snapshot must
      // not be handed back here: with no live list to check it against there
      // is no way to know whose it is.
      if (saved.isNotEmpty && accounts.isEmpty) return null;

      final scoped = scopeSnapshot(body, saved: saved, live: accounts);
      if (scoped == null) return null;
      return (
        snapshot: InsightSnapshot.fromJson(scoped.json),
        verdict: scoped.verdict,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes [snapshot] together with the accounts it was built from.
  ///
  /// Omitting [accounts] stores an unscoped record, which [load] hands back to
  /// anyone — right for demo mode and for tests, wrong for real mail. Every
  /// production caller passes the live list.
  Future<void> save(
    InsightSnapshot snapshot, {
    List<String> accounts = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'accounts': accounts, 'snapshot': snapshot.toJson()}),
    );
    // Legacy copies are stale now and would win the read order on a
    // downgrade. Dropping them also means the migration runs once per device.
    for (final legacy in _legacyKeys) {
      await prefs.remove(legacy);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    for (final legacy in _legacyKeys) {
      await prefs.remove(legacy);
    }
  }

  /// Merges fresh extractions into [previous], deduping by natural key and
  /// keeping the most recent version of each insight.
  InsightSnapshot merge(InsightSnapshot? previous, InsightSnapshot fresh) {
    // A null previous still goes through mergeBy: the same bill often arrives
    // via two emails in one sync, and the keyed map is what collapses them.
    previous ??= const InsightSnapshot();

    List<T> mergeBy<T>(
      List<T> old,
      List<T> latest,
      String Function(T) key,
      DateTime Function(T) seen,
    ) {
      final map = <String, T>{for (final item in old) key(item): item};
      for (final item in latest) {
        final existing = map[key(item)];
        if (existing == null || seen(item).isAfter(seen(existing))) {
          map[key(item)] = item;
        }
      }
      return map.values.toList();
    }

    return fresh.copyWith(
      subscriptions: mergeBy(previous.subscriptions, fresh.subscriptions,
          (s) => s.dedupeKey, (s) => s.lastSeen),
      bills: mergeBy(
          previous.bills, fresh.bills, (b) => b.dedupeKey, (b) => b.lastSeen),
      deliveries: mergeBy(previous.deliveries, fresh.deliveries,
          (d) => d.dedupeKey, (d) => d.lastSeen),
      events: mergeBy(previous.events, fresh.events, (e) => e.dedupeKey,
          (e) => e.lastSeen),
      feed: mergeBy(previous.feed, fresh.feed, (f) => f.dedupeKey,
          (f) => f.lastSeen),
      travel: mergeBy(previous.travel, fresh.travel, (t) => t.dedupeKey,
          (t) => t.lastSeen),
      payments: mergeBy(previous.payments, fresh.payments, (p) => p.dedupeKey,
          (p) => p.lastSeen),
      returns: mergeBy(previous.returns, fresh.returns, (r) => r.dedupeKey,
          (r) => r.lastSeen),
      learned: mergeBy(previous.learned, fresh.learned, (l) => l.dedupeKey,
          (l) => l.lastSeen),
      // Price changes have no `lastSeen` (they are derived, not extracted) and
      // expire on their own clock, so they get their own merge. Doing it here
      // rather than at the call site means no caller can accidentally drop the
      // history the detector depends on.
      priceChanges:
          mergePriceChanges(previous.priceChanges, fresh.priceChanges),
    );
  }
}
