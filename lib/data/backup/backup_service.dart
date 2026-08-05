import '../../domain/backup_bundle.dart';
import '../../domain/knowledge.dart';
import '../../domain/models.dart';
import '../../domain/scan_settings.dart';
import '../../domain/ignore_list.dart';
import '../store/ignore_store.dart';
import '../store/insight_store.dart';
import '../store/knowledge_store.dart';
import '../store/settings_store.dart';
import '../store/timeline_order_store.dart';
import 'backup_target.dart';

/// The result of a restore, so the UI can say exactly what came back.
class RestoreOutcome {
  final int insightCount;
  final int learnedTypeCount;
  final bool settingsRestored;
  const RestoreOutcome({
    required this.insightCount,
    required this.learnedTypeCount,
    required this.settingsRestored,
  });
}

/// Aggregates the four on-device stores into a [BackupBundle] and puts a bundle
/// back. It knows the stores; the [BackupTarget] knows the cloud. Neither knows
/// the other, so a new destination or a new store is a one-line change.
class BackupService {
  final InsightStore insights;
  final KnowledgeStore knowledge;
  final SettingsStore settings;
  final TimelineOrderStore timeline;
  final IgnoreStore ignores;

  const BackupService({
    required this.insights,
    required this.knowledge,
    required this.settings,
    required this.timeline,
    this.ignores = const IgnoreStore(),
  });

  /// Reads everything currently on the device into one bundle. [now] is
  /// injectable so tests are deterministic.
  Future<BackupBundle> collect({
    required String deviceLabel,
    String? accountEmail,
    DateTime? now,
  }) async {
    final snapshot = await insights.load();
    final playbook = await knowledge.load();
    final scan = await settings.load();
    final order = await timeline.load();
    final corrections = await ignores.load();

    return BackupBundle(
      createdAt: now ?? DateTime.now(),
      deviceLabel: deviceLabel,
      accountEmail: accountEmail,
      snapshot: snapshot?.toJson(),
      playbook: playbook.isEmpty ? null : playbook.toJson(),
      settings: scan.toJson(),
      timelineOrder: order,
      ignores: corrections.isEmpty ? null : corrections.toJson(),
    );
  }

  /// Writes a bundle's contents back into the stores, section by section. A
  /// missing section is skipped, never nulled — restoring a settings-only
  /// backup must not wipe existing insights.
  Future<RestoreOutcome> restore(BackupBundle bundle) async {
    var restoredInsights = 0;
    var restoredTypes = 0;
    var restoredSettings = false;

    final snap = bundle.snapshot;
    if (snap != null) {
      final s = InsightSnapshot.fromJson(snap);
      await insights.save(s);
      restoredInsights = bundle.insightCount;
    }

    final pb = bundle.playbook;
    if (pb != null) {
      final playbook = Playbook.fromJson(pb);
      await knowledge.save(playbook);
      restoredTypes = bundle.learnedTypeCount;
    }

    final st = bundle.settings;
    if (st != null) {
      await settings.save(ScanSettings.fromJson(st));
      restoredSettings = true;
    }

    if (bundle.timelineOrder.isNotEmpty) {
      await timeline.save(bundle.timelineOrder);
    }

    final corrections = bundle.ignores;
    if (corrections != null) {
      await ignores.save(IgnoreList.fromJson(corrections));
    }

    return RestoreOutcome(
      insightCount: restoredInsights,
      learnedTypeCount: restoredTypes,
      settingsRestored: restoredSettings,
    );
  }

  /// Convenience: collect, then upload to [target].
  Future<BackupMeta> backUpTo(
    BackupTarget target, {
    required String deviceLabel,
    String? accountEmail,
    DateTime? now,
  }) async {
    final bundle = await collect(
      deviceLabel: deviceLabel,
      accountEmail: accountEmail,
      now: now,
    );
    await target.upload(bundle);
    return BackupMeta.of(bundle);
  }

  /// Convenience: download from [target] and restore. Returns null if the
  /// destination held no backup.
  Future<RestoreOutcome?> restoreFrom(BackupTarget target) async {
    final bundle = await target.download();
    if (bundle == null) return null;
    return restore(bundle);
  }
}
