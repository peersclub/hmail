import 'dart:convert';

/// A single, portable snapshot of everything NoMail has learned and computed —
/// the equivalent of a WhatsApp chat backup. It aggregates the JSON of all four
/// on-device stores into one versioned document that a [BackupTarget] can write
/// to iCloud or Google Drive and read back on a fresh install.
///
/// The crown jewel here is [playbook]: the AI-earned recipes that took real
/// model calls to learn. Insights re-derive from a rescan; the playbook does
/// not, so a restore is what makes a reinstall feel instant instead of naive.
class BackupBundle {
  /// Schema version of the *bundle envelope* (not the inner store payloads,
  /// which carry their own versioning and per-key fallbacks in fromJson).
  static const currentVersion = 1;

  final int version;
  final DateTime createdAt;

  /// Human label for the source device, e.g. "Victor's iPhone" — shown in the
  /// restore picker so a user with several devices knows which backup is which.
  final String deviceLabel;

  /// The account the backup belongs to, when known — lets the UI warn before
  /// restoring one account's data onto another.
  final String? accountEmail;

  /// Raw `toJson()` of each store. Nullable so a partial/empty app still backs
  /// up cleanly; restore simply skips a missing section.
  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic>? playbook;
  final Map<String, dynamic>? settings;
  final List<String> timelineOrder;

  const BackupBundle({
    this.version = currentVersion,
    required this.createdAt,
    required this.deviceLabel,
    this.accountEmail,
    this.snapshot,
    this.playbook,
    this.settings,
    this.timelineOrder = const [],
  });

  /// Rough item count for the UI summary ("1,204 insights · 18 learned types"),
  /// read straight off the raw maps so the bundle needn't import the models.
  int get insightCount {
    final s = snapshot;
    if (s == null) return 0;
    var n = 0;
    for (final v in s.values) {
      if (v is List) n += v.length;
    }
    return n;
  }

  int get learnedTypeCount {
    final p = playbook;
    if (p == null) return 0;
    final types = p['types'];
    return types is List ? types.length : 0;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'deviceLabel': deviceLabel,
        'accountEmail': accountEmail,
        'snapshot': snapshot,
        'playbook': playbook,
        'settings': settings,
        'timelineOrder': timelineOrder,
      };

  factory BackupBundle.fromJson(Map<String, dynamic> json) => BackupBundle(
        version: (json['version'] as num?)?.toInt() ?? currentVersion,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        deviceLabel: json['deviceLabel'] as String? ?? 'Unknown device',
        accountEmail: json['accountEmail'] as String?,
        snapshot: (json['snapshot'] as Map?)?.cast<String, dynamic>(),
        playbook: (json['playbook'] as Map?)?.cast<String, dynamic>(),
        settings: (json['settings'] as Map?)?.cast<String, dynamic>(),
        timelineOrder:
            (json['timelineOrder'] as List?)?.cast<String>() ?? const [],
      );

  /// Serialized bytes as stored in the cloud. UTF-8 JSON — small, diffable,
  /// and readable, which matters when a user asks "what's in my backup?".
  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  factory BackupBundle.fromBytes(List<int> bytes) =>
      BackupBundle.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  int get sizeBytes => toBytes().length;
}
