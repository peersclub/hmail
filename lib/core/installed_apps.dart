/// Which of the catalog's apps are actually on this phone.
///
/// This is the only platform-touching half of app detection;
/// `domain/app_targets.dart` holds the knowledge and stays pure.
///
/// WHY WE PROBE CUSTOM SCHEMES AND NEVER https
/// `canLaunchUrl(Uri.parse('https://delhivery.com'))` returns true on every
/// iPhone ever made — Safari can open it, so the answer says nothing about
/// whether the Delhivery app is installed. iOS exposes no API for "does this
/// app claim this domain?". The only signal available is
/// `canLaunchUrl('delhivery://')`, which is true only when the app is present
/// AND `delhivery` is declared in `LSApplicationQueriesSchemes`. So: probe the
/// scheme, then launch the https universal link (officially supported, lands
/// on the right page) rather than a guessed `app://path` that fails silently.
///
/// WHY THE RESULT IS CACHED FOR THE SESSION
/// A full sweep is ~40 platform-channel round trips. Insight cards ask "is
/// PhonePe installed?" while building, and a list can rebuild many times per
/// second — re-probing on every tap would burn the main thread for an answer
/// that only changes when the user installs or deletes an app. One sweep per
/// session is the right trade; [refresh] exists for the rare case where the
/// app wants to re-check (e.g. after returning from the App Store).
library;

import 'package:url_launcher/url_launcher.dart';

import '../domain/app_targets.dart';

/// Probes the device for the catalog's apps and remembers the answer.
///
/// Inject [probe] in tests so nothing touches the platform:
/// ```dart
/// InstalledApps(probe: (uri) async => uri.scheme == 'phonepe');
/// ```
class InstalledApps {
  InstalledApps({Future<bool> Function(Uri)? probe})
      : _probe = probe ?? _platformProbe;

  final Future<bool> Function(Uri) _probe;

  /// Session cache of installed [AppTarget.key]s. Null until the first sweep
  /// completes — see the class doc for why this exists.
  Set<String>? _cache;

  /// De-duplicates concurrent first calls so a rebuild storm triggers one
  /// sweep, not one per caller.
  Future<Set<String>>? _inFlight;

  static Future<bool> _platformProbe(Uri uri) => canLaunchUrl(uri);

  /// Keys of every catalog app detected on the device.
  ///
  /// Cached after the first call; never throws — a failed probe counts as
  /// "not installed", because guessing "installed" would send the user into a
  /// dead end instead of the web fallback.
  Future<Set<String>> detect() {
    final cached = _cache;
    if (cached != null) return Future<Set<String>>.value(cached);
    return _inFlight ??= _sweep();
  }

  /// Drops the cache and re-probes. Use after the user may have installed or
  /// removed an app (returning from the App Store, app resumed from
  /// background).
  Future<void> refresh() async {
    _cache = null;
    _inFlight = null;
    await detect();
  }

  Future<bool> has(String key) async => (await detect()).contains(key);

  /// Synchronous read for `build` methods that cannot await: the answer if a
  /// sweep has already completed, or null for "not known yet" — render the
  /// neutral state and let [detect] settle it.
  bool? knownHas(String key) => _cache?.contains(key);

  /// What the last sweep found, or empty if it hasn't finished. For callers
  /// that must decide *now* and would rather assume "no apps" than wait —
  /// assuming none is always safe, since it only routes to the web.
  Set<String> get known => _cache ?? const {};

  /// True once a sweep has completed, so [knownHas] returns real answers.
  bool get isReady => _cache != null;

  Future<Set<String>> _sweep() async {
    try {
      final targets = AppCatalog.all
          .where((t) => t.probeUri != null)
          .toList(growable: false);
      final results = await Future.wait(
        targets.map((t) => _probeOne(t.probeUri!)),
      );
      final found = <String>{};
      for (var i = 0; i < targets.length; i++) {
        if (results[i]) found.add(targets[i].key);
      }
      _cache = found;
      return found;
    } catch (_) {
      // Belt-and-braces: _probeOne already swallows per-app failures, so this
      // only fires if something structural broke. Empty set = "use the web".
      final empty = <String>{};
      _cache = empty;
      return empty;
    } finally {
      _inFlight = null;
    }
  }

  /// One probe, failure-proof. url_launcher throws on iOS when a scheme is
  /// missing from `LSApplicationQueriesSchemes`; that is a build-config bug,
  /// not a crash worth shipping.
  Future<bool> _probeOne(Uri uri) async {
    try {
      return await _probe(uri);
    } catch (_) {
      return false;
    }
  }
}
