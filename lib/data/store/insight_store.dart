import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';

/// Local-first persistence: the last snapshot renders instantly on launch;
/// sync refreshes it in place.
class InsightStore {
  // Bump when extraction logic changes materially — forces a clean re-extract
  // instead of merging against stale results.
  static const _key = 'insight_snapshot_v4';

  Future<InsightSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return InsightSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(InsightSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
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
    );
  }
}
