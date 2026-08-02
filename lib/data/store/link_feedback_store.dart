import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/link_feedback.dart';

/// Persistence for link feedback.
///
/// Mirrors [InsightStore]: versioned key, defensive decode. Corrupt data
/// returns an empty log rather than null — feedback is advisory, and a callsite
/// that has to null-check a diagnostic log will eventually forget to.
class LinkFeedbackStore {
  // Bump when the feedback schema changes materially.
  static const _key = 'link_feedback_v1';

  Future<LinkFeedbackLog> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const LinkFeedbackLog();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const LinkFeedbackLog();
      return LinkFeedbackLog.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const LinkFeedbackLog();
    }
  }

  Future<void> save(LinkFeedbackLog log) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(_key, jsonEncode(log.toJson()));
    } catch (_) {
      // Losing a thumbs-up must never break the action the user just took.
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Read-modify-write convenience: the common case is one answer at a time.
  Future<LinkFeedbackLog> append(LinkFeedback feedback) async {
    final updated = (await load()).add(feedback);
    await save(updated);
    return updated;
  }
}
