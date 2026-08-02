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
  /// Lazily produces an authorized DriveApi (or null if the user isn't signed
  /// in / declined the scope). Injected so tests can supply a fake, and so the
  /// target holds no auth state of its own.
  final Future<drive.DriveApi?> Function() connect;

  static const _fileName = 'nomail-backup.json';

  const DriveBackupTarget(this.connect);

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive';

  @override
  Future<bool> isAvailable() async => (await connect()) != null;

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
    final api = await connect();
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
    final api = await connect();
    if (api == null) {
      throw const BackupException('Sign in to Google to back up to Drive');
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
    final api = await connect();
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
