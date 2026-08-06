/// How often NoMail backs itself up. Phones have no always-on scheduler, so
/// "daily"/"weekly" mean "opportunistically, after a sync, once this much time
/// has passed" — the honest mobile equivalent of WhatsApp's nightly job.
enum BackupFrequency {
  off('Off', null),
  daily('Daily', Duration(days: 1)),
  weekly('Weekly', Duration(days: 7));

  const BackupFrequency(this.label, this.interval);
  final String label;
  final Duration? interval;

  static BackupFrequency fromName(String? name) => values.firstWhere(
        (f) => f.name == name,
        orElse: () => BackupFrequency.off,
      );
}

/// User's backup configuration and the timestamp of the last successful run.
class BackupPrefs {
  /// Destination id — matches a [BackupTarget.id] ('gdrive', 'icloud').
  final String destinationId;
  final BackupFrequency frequency;
  final DateTime? lastBackupAt;

  /// [frequency] defaults to daily — a device that has never opened the backup
  /// screen still gets a cloud copy, because the people who most need one are
  /// exactly the people who never went looking for the setting.
  ///
  /// It costs nothing unauthorized: `_maybeAutoBackup` runs only when the
  /// destination is *already* authorized and never raises a consent sheet, so
  /// on a device that has not connected Drive this default does nothing at all.
  /// A user who explicitly chose Off has that stored and keeps it — this
  /// default applies only where there is no stored answer.
  const BackupPrefs({
    this.destinationId = 'gdrive',
    this.frequency = BackupFrequency.daily,
    this.lastBackupAt,
  });

  /// Whether an opportunistic auto-backup is due given [now].
  bool isDue(DateTime now) {
    final interval = frequency.interval;
    if (interval == null) return false; // Off
    final last = lastBackupAt;
    if (last == null) return true; // never backed up
    return now.difference(last) >= interval;
  }

  BackupPrefs copyWith({
    String? destinationId,
    BackupFrequency? frequency,
    DateTime? lastBackupAt,
    bool clearLastBackup = false,
  }) =>
      BackupPrefs(
        destinationId: destinationId ?? this.destinationId,
        frequency: frequency ?? this.frequency,
        lastBackupAt:
            clearLastBackup ? null : (lastBackupAt ?? this.lastBackupAt),
      );

  Map<String, dynamic> toJson() => {
        'destinationId': destinationId,
        'frequency': frequency.name,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
      };

  factory BackupPrefs.fromJson(Map<String, dynamic> json) => BackupPrefs(
        destinationId: json['destinationId'] as String? ?? 'gdrive',
        frequency: BackupFrequency.fromName(json['frequency'] as String?),
        lastBackupAt: json['lastBackupAt'] == null
            ? null
            : DateTime.tryParse(json['lastBackupAt'] as String),
      );
}
