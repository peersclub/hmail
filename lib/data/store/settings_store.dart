import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/scan_settings.dart';

/// Persists the user's scan preferences. Unlike the insight snapshot, absent or
/// unreadable settings are never an error state — we fall back to defaults so
/// the app always has something valid to scan with.
class SettingsStore {
  // Bump when a field's meaning changes incompatibly; additive fields are
  // handled by ScanSettings.fromJson's per-key fallbacks instead.
  static const _key = 'scan_settings_v1';

  /// Dedicated key (not inside the scan JSON) so schema churn never re-shows
  /// the first-run carousel.
  static const _seenOnboardingKey = 'seen_onboarding';

  Future<ScanSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const ScanSettings();
    try {
      return ScanSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ScanSettings();
    }
  }

  Future<void> save(ScanSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  Future<bool> loadSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenOnboardingKey) ?? false;
  }

  Future<void> setSeenOnboarding(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenOnboardingKey, seen);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
