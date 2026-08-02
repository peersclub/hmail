import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/knowledge.dart';

/// Persistence for the learned playbook.
///
/// The playbook is the app's accumulated understanding of email shapes — every
/// entry cost an AI call to author, so losing it means paying to relearn the
/// whole inbox. Reads are therefore forgiving: a corrupt or partially written
/// blob degrades to an empty playbook (relearn) rather than an exception on
/// launch.
class KnowledgeStore {
  /// Bump when the entry schema changes in a way old records cannot satisfy —
  /// a version bump discards the learned set and the AI reteaches itself.
  static const _key = 'playbook_v1';

  /// Never returns null: "nothing learned yet" and "the stored blob was
  /// garbage" are the same situation for every caller.
  Future<Playbook> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const Playbook();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const Playbook();
      return Playbook.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const Playbook();
    }
  }

  Future<void> save(Playbook playbook) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(playbook.toJson()));
    } catch (_) {
      // A failed write costs a relearn, never a crash mid-sync.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nothing to do — the key is already unreadable.
    }
  }
}
