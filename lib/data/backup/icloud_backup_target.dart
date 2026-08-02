import 'package:flutter/services.dart';

import '../../domain/backup_bundle.dart';
import 'backup_target.dart';

/// iCloud Drive backup, stored as a single file in the app's iCloud ubiquity
/// container — the WhatsApp "Back Up to iCloud" model. The Dart side talks to a
/// tiny native handler over a [MethodChannel]; the native side reads/writes the
/// file in `URLForUbiquityContainerIdentifier`.
///
/// Degrades safely: if the native handler isn't present (channel not
/// registered) or the iCloud capability/container isn't provisioned, every
/// call reports the destination as unavailable instead of crashing, so the app
/// keeps working on Google Drive. Enabling iCloud is then purely additive —
/// register the channel and turn on the iCloud capability in Xcode.
class ICloudBackupTarget implements BackupTarget {
  static const _channel = MethodChannel('com.nomail.nomail/icloud');

  const ICloudBackupTarget();

  @override
  String get id => 'icloud';

  @override
  String get label => 'iCloud';

  @override
  Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<BackupMeta?> latest() async {
    final bundle = await download();
    return bundle == null ? null : BackupMeta.of(bundle);
  }

  @override
  Future<void> upload(BackupBundle bundle) async {
    try {
      final bytes = Uint8List.fromList(bundle.toBytes());
      await _channel.invokeMethod<void>('write', {'bytes': bytes});
    } on MissingPluginException {
      throw const BackupException('iCloud isn\'t set up on this build');
    } on PlatformException catch (e) {
      throw BackupException(e.message ?? 'iCloud backup failed', e);
    }
  }

  @override
  Future<BackupBundle?> download() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('read');
      if (bytes == null || bytes.isEmpty) return null;
      return BackupBundle.fromBytes(bytes);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw BackupException(e.message ?? 'iCloud restore failed', e);
    }
  }
}
