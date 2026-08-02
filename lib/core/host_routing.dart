import 'package:shared_preferences/shared_preferences.dart';

/// Hosts the user has taught NoMail to open *outside* the in-app browser.
///
/// Detection can never know every app: iOS caps `LSApplicationQueriesSchemes`
/// at 50, so the probe registry stops at the big names — and a WKWebView never
/// triggers universal links, which means an unknown merchant's link rendered
/// in-app is *guaranteed* to bypass their installed app (the Ubuy lesson).
/// The scalable fix is memory, not a bigger registry: one "open outside" tap
/// in the WebView records the host, and from then on that site is handed to
/// iOS — which routes it to the app when one claims it, else Safari.
class HostRouting {
  static const _key = 'external_hosts_v1';

  Set<String>? _cache;

  /// The remembered hosts, without waiting — empty until [load] first runs.
  Set<String> get known => _cache ?? const {};

  Future<Set<String>> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    _cache = (prefs.getStringList(_key) ?? const []).toSet();
    return _cache!;
  }

  Future<void> preferExternal(String host) async {
    final set = await load();
    set.add(normalize(host));
    await _save(set);
  }

  Future<void> undo(String host) async {
    final set = await load();
    set.remove(normalize(host));
    await _save(set);
  }

  Future<void> _save(Set<String> set) async {
    _cache = set;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, set.toList()..sort());
  }

  /// `www.ubuy.co.in` and `ubuy.co.in` are the same site to a person, so the
  /// stored form drops the www and matching checks the suffix.
  static String normalize(String host) {
    final lower = host.toLowerCase();
    return lower.startsWith('www.') ? lower.substring(4) : lower;
  }

  /// Whether [host] (raw, from a URL) matches any remembered host.
  static bool matches(String host, Set<String> remembered) {
    final normalized = normalize(host);
    return remembered.any(
        (r) => normalized == r || normalized.endsWith('.$r'));
  }
}

/// Shared across the app: the sheet reads it to plan, the WebView writes it.
final HostRouting hostRouting = HostRouting();
