import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/backup_prefs.dart';

/// Persists the user's backup destination, frequency, and last-run time.
class BackupPrefsStore {
  static const _key = 'backup_prefs_v1';

  Future<BackupPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const BackupPrefs();
    try {
      return BackupPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const BackupPrefs();
    }
  }

  Future<void> save(BackupPrefs value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value.toJson()));
  }
}
