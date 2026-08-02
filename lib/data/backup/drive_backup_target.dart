import 'dart:io' show SocketException;

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../data/mail/gmail_auth.dart' show DriveAuth, DriveAuthIssue;
import '../../domain/backup_bundle.dart';
import 'backup_target.dart';

/// Google Drive backup, stored in the app-data folder — the same hidden,
/// per-app space WhatsApp-style backups use. The file never appears in the
/// user's Drive and no other app can read it.
///
/// A single file, `nomail-backup.json`, is created once and overwritten in
/// place on each backup, so the destination always holds exactly the latest.
///
/// Every failure path maps to a [BackupException] whose message names the
/// actual cause and what to do about it — "backup failed" alone is banned.
class DriveBackupTarget implements BackupTarget {
  /// Whether a Google account is connected — a cheap check with no consent
  /// prompt, so it's safe on screen load. "Available" means "a backup can be
  /// attempted"; the Drive-scope grant itself happens on the first upload.
  final Future<bool> Function() signedIn;

  /// Produces an authorized DriveApi or the reason it couldn't. [interactive]
  /// true may show the Google consent sheet, so it's passed only from
  /// upload/download (explicit user actions) — never from [isAvailable],
  /// [isAuthorized], or [latest].
  final Future<DriveAuth> Function({bool interactive}) connect;

  static const _fileName = 'nomail-backup.json';

  const DriveBackupTarget({required this.signedIn, required this.connect});

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive';

  @override
  Future<bool> isAvailable() async => signedIn();

  @override
  Future<bool> isAuthorized() async =>
      (await connect(interactive: false)).api != null;

  @override
  Future<BackupMeta?> latest() async {
    // Silent: only reads metadata if Drive was already granted. Never prompts.
    final api = (await connect(interactive: false)).api;
    if (api == null) return null;
    try {
      final bundle = await _download(api);
      return bundle == null ? null : BackupMeta.of(bundle);
    } catch (e) {
      throw _mapError(e, doing: 'reading your backup');
    }
  }

  @override
  Future<void> upload(BackupBundle bundle) async {
    // Explicit user action — may show the Google consent sheet the first time.
    final auth = await connect(interactive: true);
    final api = auth.api;
    if (api == null) throw _authException(auth.issue);
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
      throw _mapError(e, doing: 'saving your backup');
    }
  }

  @override
  Future<BackupBundle?> download() async {
    // Explicit user action (Restore) — interactive, so a fresh install can
    // grant Drive and pull its backup in one step.
    final auth = await connect(interactive: true);
    final api = auth.api;
    if (api == null) throw _authException(auth.issue);
    try {
      return await _download(api);
    } catch (e) {
      throw _mapError(e, doing: 'fetching your backup');
    }
  }

  Future<drive.File?> _find(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      $fields: 'files(id,modifiedTime,size)',
    );
    final files = res.files;
    return (files == null || files.isEmpty) ? null : files.first;
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

  /// Authorization failures, each with its own recovery.
  BackupException _authException(DriveAuthIssue? issue) => switch (issue) {
        DriveAuthIssue.notSignedIn => const BackupException(
            'Connect a Google account first — backup uses the same account '
            'as your mail.'),
        DriveAuthIssue.declined => const BackupException(
            'Permission was declined. NoMail only uses its own private '
            'folder in your Drive — tap again and choose Allow.'),
        _ => const BackupException(
            'Couldn\'t reach Google to ask for Drive access. Check your '
            'connection and try again.'),
      };

  /// API-level failures, translated from Google's error surface into a cause
  /// the user (or the developer reading the same words) can act on.
  BackupException _mapError(Object e, {required String doing}) {
    if (e is BackupException) return e;
    if (e is drive.DetailedApiRequestError) {
      final msg = e.message ?? '';
      if (e.status == 403 &&
          (msg.contains('has not been used') ||
              msg.contains('is disabled') ||
              msg.contains('accessNotConfigured'))) {
        return BackupException(
            'Google Drive access isn\'t switched on for NoMail\'s Google '
            'project yet. Enable the Drive API in Google Cloud Console, '
            'then try again.', e);
      }
      if (e.status == 403) {
        return BackupException(
            'Google refused Drive access. Tap Back Up Now and choose Allow '
            'when Google asks.', e);
      }
      if (e.status == 401) {
        return BackupException(
            'Your Google session expired. Sign out and back in, then retry.',
            e);
      }
      return BackupException(
          'Google Drive returned an error (${e.status}) while $doing. '
          'Try again in a moment.', e);
    }
    if (e is SocketException || e is http.ClientException) {
      return BackupException(
          'Couldn\'t reach Google Drive while $doing. Check your '
          'connection and try again.', e);
    }
    return BackupException('Something went wrong while $doing. Try again.', e);
  }
}
