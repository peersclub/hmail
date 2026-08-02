import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's preferred order of Timeline domain chips. Stored as a
/// list of `InsightDomain.name` strings; unknown/new domains simply append.
class TimelineOrderStore {
  static const _key = 'timeline_domain_order_v1';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  Future<void> save(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, order);
  }
}
