import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The OpenRouter API key, from either of two places — a key the user pasted
/// into the app (persisted, wins) or the developer's `.env` (fallback).
///
/// Before this existed the AI screen told users to "add OPENROUTER_API_KEY to
/// .env" — an instruction no phone user can follow. Now the key is a setting.
///
/// Storage honesty: SharedPreferences is the app sandbox, not the Keychain.
/// Acceptable for a spend-capped OpenRouter key the user can revoke; if the
/// app ever holds a more powerful credential, move this to Keychain-backed
/// storage.
class AiKey {
  static const _prefsKey = 'openrouter_api_key_v1';

  /// In-memory cache so [value] stays synchronous like dotenv (the AI call
  /// sites are hot paths that read it per request).
  static String? _runtime;

  /// The effective key, or null when neither source has one.
  static String? get value {
    final user = _runtime?.trim();
    if (user != null && user.isNotEmpty) return user;
    final env = dotenv.maybeGet('OPENROUTER_API_KEY')?.trim();
    return (env == null || env.isEmpty) ? null : env;
  }

  /// Whether the effective key came from the user (vs the developer .env) —
  /// drives the "Remove key" affordance, which must not offer to remove a
  /// key it can't actually remove.
  static bool get isUserProvided =>
      _runtime != null && _runtime!.trim().isNotEmpty;

  /// Loads the user's stored key into memory. Call once at app start.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _runtime = prefs.getString(_prefsKey);
  }

  static Future<void> save(String key) async {
    _runtime = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _runtime!);
  }

  static Future<void> clear() async {
    _runtime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
