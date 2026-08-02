import '../../domain/backup_bundle.dart';

/// Lightweight description of the newest backup at a destination, shown in the
/// Backup screen without downloading the whole bundle.
class BackupMeta {
  final DateTime createdAt;
  final int sizeBytes;
  final int version;
  final String deviceLabel;
  final String? accountEmail;

  /// What's inside — lets the restore confirmation say "214 insights and
  /// 6 learned types" instead of asking the user to trust a file blindly.
  final int insightCount;
  final int learnedTypeCount;

  const BackupMeta({
    required this.createdAt,
    required this.sizeBytes,
    required this.version,
    required this.deviceLabel,
    this.accountEmail,
    this.insightCount = 0,
    this.learnedTypeCount = 0,
  });

  factory BackupMeta.of(BackupBundle b) => BackupMeta(
        createdAt: b.createdAt,
        sizeBytes: b.sizeBytes,
        version: b.version,
        deviceLabel: b.deviceLabel,
        accountEmail: b.accountEmail,
        insightCount: b.insightCount,
        learnedTypeCount: b.learnedTypeCount,
      );
}

/// A place a [BackupBundle] can be written to and read back — iCloud, Google
/// Drive, or an in-memory fake. The backup service is written entirely against
/// this interface and never knows which cloud is behind it.
///
/// Every method may throw [BackupException]; callers surface the message.
abstract interface class BackupTarget {
  /// Stable id used to persist the user's chosen destination — 'icloud',
  /// 'gdrive', 'memory'.
  String get id;

  /// Human label for the destination toggle.
  String get label;

  /// Whether this destination can be used right now (entitlement present,
  /// signed in, container reachable). The UI greys out unavailable targets
  /// rather than letting a backup fail mid-flight.
  Future<bool> isAvailable();

  /// Whether the destination can be written *silently* — no consent sheet,
  /// no user interaction. Automatic background backups run only when this is
  /// true; a surprise permission popup after a sync would be hostile.
  Future<bool> isAuthorized();

  /// Metadata of the newest backup, or null if none exists yet.
  Future<BackupMeta?> latest();

  /// Writes [bundle], replacing any previous backup for this app.
  Future<void> upload(BackupBundle bundle);

  /// Reads the newest backup, or null if none exists.
  Future<BackupBundle?> download();
}

/// A destination failure with a message safe to show the user.
class BackupException implements Exception {
  final String message;
  final Object? cause;
  const BackupException(this.message, [this.cause]);

  @override
  String toString() => 'BackupException: $message';
}

/// In-memory target: the null destination (backup effectively off) and the
/// fake the tests drive. Keeps exactly one bundle, like the real clouds.
class MemoryBackupTarget implements BackupTarget {
  BackupBundle? _stored;
  final bool available;

  MemoryBackupTarget({this.available = true, BackupBundle? seed})
      : _stored = seed;

  @override
  String get id => 'memory';

  @override
  String get label => 'On this device';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isAuthorized() async => available;

  @override
  Future<BackupMeta?> latest() async =>
      _stored == null ? null : BackupMeta.of(_stored!);

  @override
  Future<void> upload(BackupBundle bundle) async {
    if (!available) throw const BackupException('Destination unavailable');
    _stored = bundle;
  }

  @override
  Future<BackupBundle?> download() async => _stored;
}
