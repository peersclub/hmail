/// Which account's insights these are, and how to keep that true.
///
/// WHY A STORED SNAPSHOT IS NOT SELF-CONTAINED
/// Every insight names its source email as `a<N>:<gmailId>`, where N is a
/// *position* in the signed-in account list (see MultiGmailSource). Positions
/// are only meaningful next to the list they were taken from: sign in again
/// with the accounts in another order and `a0:` now names a different inbox.
/// Acting on that would open one person's mail from another person's insight —
/// so a snapshot is stored together with the account list it was built against,
/// and reconciled against the live one before it is ever shown.
///
/// THREE OUTCOMES, AND WHY THE STRICT ONE IS THE DEFAULT
/// The same account returns and everything is restored. Some accounts
/// overlap, so the overlap is remapped and the rest dropped — a partial
/// restore, because half the user's data is worth more than none. Or nothing
/// overlaps, which means a different person is holding the phone, and the
/// right answer is to show them nothing at all.
///
/// Pure Dart, and deliberately operating on JSON rather than on typed models:
/// a walk keyed on `sourceEmailId` cannot fall behind, whereas a new insight
/// type would silently miss a `copyWith`-based remap and keep a stale index.
library;

final _prefixed = RegExp(r'^a(\d+):(.+)$');

/// How a stored snapshot relates to the accounts signed in now.
enum AccountScope {
  /// Same accounts, same order — restore verbatim.
  identical,

  /// Some accounts survive; their indices moved. Restore the overlap.
  remapped,

  /// No stored account is signed in. Restore nothing.
  foreign,
}

/// The comparison of a stored account list against the live one.
class ScopeVerdict {
  final AccountScope scope;

  /// Insights dropped because their account is no longer connected. Surfaced
  /// so a partial restore can be reported rather than looking like data loss.
  final int droppedInsights;

  const ScopeVerdict(this.scope, {this.droppedInsights = 0});
}

/// Reconciles a stored snapshot's account indices with [live].
///
/// [saved] is the ordered account list in force when the snapshot was written;
/// [live] is the one in force now. Returns the JSON to restore, or null when
/// nothing in it belongs to the current user.
///
/// An id with no `a<N>:` prefix is left exactly as found. Demo fixtures and
/// pre-multi-account snapshots look like that, and rewriting them would be
/// inventing an account that was never recorded.
({Map<String, dynamic> json, ScopeVerdict verdict})? scopeSnapshot(
  Map<String, dynamic> json, {
  required List<String> saved,
  required List<String> live,
}) {
  // No account list recorded: a snapshot from before scoping existed. It is
  // this device's own data and there is no evidence it belongs to anyone else,
  // so it is restored untouched — the alternative is deleting a user's history
  // on upgrade.
  if (saved.isEmpty) {
    return (json: json, verdict: const ScopeVerdict(AccountScope.identical));
  }

  // Positions, not identities, are what the prefixes encode — so the map is
  // built by looking each saved email up in the live list.
  final moved = <int, int>{};
  for (var i = 0; i < saved.length; i++) {
    final now = live.indexOf(saved[i]);
    if (now >= 0) moved[i] = now;
  }
  if (moved.isEmpty) {
    return null; // Someone else's phone session. Show them nothing.
  }

  final unchanged = moved.length == saved.length &&
      moved.entries.every((e) => e.key == e.value);

  var dropped = 0;
  final result = <String, dynamic>{};
  for (final entry in json.entries) {
    final value = entry.value;
    if (value is! List) {
      result[entry.key] = value;
      continue;
    }
    final kept = <dynamic>[];
    for (final item in value) {
      if (item is! Map) {
        kept.add(item);
        continue;
      }
      final id = item['sourceEmailId'];
      if (id is! String) {
        kept.add(item);
        continue;
      }
      final match = _prefixed.firstMatch(id);
      if (match == null) {
        kept.add(item); // Unprefixed: legacy or demo, left alone.
        continue;
      }
      final to = moved[int.parse(match.group(1)!)];
      if (to == null) {
        dropped++; // That account is gone; so is anything derived from it.
        continue;
      }
      // Explicitly typed, not a bare `{...item, …}` spread: spreading a `Map`
      // yields `Map<dynamic, dynamic>`, and every `fromJson` in the app casts
      // to `Map<String, dynamic>`. Getting this wrong throws on restore.
      kept.add(<String, dynamic>{
        for (final field in item.entries) '${field.key}': field.value,
        'sourceEmailId': 'a$to:${match.group(2)!}',
      });
    }
    result[entry.key] = kept;
  }

  return (
    json: result,
    verdict: ScopeVerdict(
      unchanged && dropped == 0 ? AccountScope.identical : AccountScope.remapped,
      droppedInsights: dropped,
    ),
  );
}
