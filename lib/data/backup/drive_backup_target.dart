import 'package:googleapis/drive/v3.dart' as drive;

import '../../domain/backup_bundle.dart';
import 'backup_target.dart';

/// Google Drive backup, stored in the app-data folder — the same hidden,
/// per-app space WhatsApp-style backups use. The file never appears in the
/// user's Drive and no other app can read it.
///
/// A single file, `nomail-backup.json`, is created once and overwritten in
/// place on each backup, so the destination always holds exactly the latest.
class DriveBackupTarget implements BackupTarget {
  /// Whether a Google account is connected — a cheap check with no consent
  /// prompt, so it's safe on screen load. "Available" means "we can attempt a
  /// backup"; the actual Drive-scope grant happens on the first upload.
  final Future<bool> Function() signedIn;

  /// Lazily produces an authorized DriveApi. [interactive] true may show the
  /// Google consent sheet, so it's passed only from upload/download (explicit
  /// user actions) — never from [isAvailable] or [latest].
  final Future<drive.DriveApi?> Function({bool interactive}) connect;

  static const _fileName = 'nomail-backup.json';

  const DriveBackupTarget({required this.signedIn, required this.connect});

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive';

  @override
  Future<bool> isAvailable() async => signedIn();

  Future<drive.File?> _find(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      $fields: 'files(id,modifiedTime,size)',
    );
    final files = res.files;
    return (files == null || files.isEmpty) ? null : files.first;
  }

  @override
  Future<BackupMeta?> latest() async {
    // Silent: only reads metadata if Drive was already granted. Never prompts.
    final api = await connect(interactive: false);
    if (api == null) return null;
    try {
      final bundle = await _download(api);
      return bundle == null ? null : BackupMeta.of(bundle);
    } catch (e) {
      throw BackupException('Could not read the Google Drive backup', e);
    }
  }

  @override
  Future<void> upload(BackupBundle bundle) async {
    // Explicit user action — may show the Google consent sheet the first time.
    final api = await connect(interactive: true);
    if (api == null) {
      throw const BackupException(
          'Sign in to Google (and allow Drive) to back up');
    }
    try {
      final bytes = bundle.toBytes();
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );
      final existing = await _find(api);
      if (existing == null) {
        final meta = drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'];
        await api.files.create(meta, uploadMedia: media);
      } else {
        await api.files.update(drive.File(), existing.id!, uploadMedia: media);
      }
    } catch (e) {
      if (e is BackupException) rethrow;
      throw BackupException('Google Drive backup failed', e);
    }
  }

  @override
  Future<BackupBundle?> download() async {
    // Explicit user action (Restore) — interactive so a fresh install can grant
    // Drive and pull the backup in one step.
    final api = await connect(interactive: true);
    if (api == null) return null;
    try {
      return await _download(api);
    } catch (e) {
      throw BackupException('Google Drive restore failed', e);
    }
  }

  Future<BackupBundle?> _download(drive.DriveApi api) async {
    final existing = await _find(api);
    if (existing == null) return null;
    final media = await api.files.get(
      existing.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return BackupBundle.fromBytes(bytes);
  }
}
