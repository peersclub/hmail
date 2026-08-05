import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/ignore_list.dart';

/// Persistence for the user's corrections.
///
/// Mirrors [LinkFeedbackStore]: versioned key, defensive decode, empty rather
/// than null on damage. These rules are user intent, not derived data — they
/// are never invalidated by a snapshot key bump, which is exactly why they get
/// their own key instead of riding inside the snapshot.
class IgnoreStore {
  const IgnoreStore();

  static const _key = 'ignore_rules_v1';

  Future<IgnoreList> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return IgnoreList.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return IgnoreList.empty;
      return IgnoreList.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return IgnoreList.empty;
    }
  }

  Future<void> save(IgnoreList list) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(_key, jsonEncode(list.toJson()));
    } catch (_) {
      // A correction that fails to persist still applies for this session.
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
