import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A Gmail account NoMail has been connected to, as remembered across
/// launches. google_sign_in 7.x only restores the platform's single active
/// session at boot, so without this record every additional account would
/// silently vanish on restart. The stored descriptor lets the UI show the
/// account with a "reconnect" journey instead of forgetting it existed.
typedef StoredAccount = ({String email, String? name, String? photoUrl});

class AccountsStore {
  static const _key = 'connected_accounts_v1';

  Future<List<StoredAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return [
        for (final entry in decoded)
          if (entry is Map && entry['email'] is String)
            (
              email: entry['email'] as String,
              name: entry['name'] as String?,
              photoUrl: entry['photoUrl'] as String?,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<StoredAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([
        for (final a in accounts)
          {'email': a.email, 'name': a.name, 'photoUrl': a.photoUrl},
      ]),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
