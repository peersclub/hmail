/// Backup & Restore — the "your insights are safe" surface.
///
/// Modelled on the WhatsApp backup flow: one place that shows when you last
/// backed up, lets you back up now, choose iCloud or Google Drive, set a
/// frequency, and restore onto a fresh install. What travels is the AI-earned
/// knowledge and computed insights — never your mail, which stays in Gmail.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../data/backup/backup_service.dart';
import '../../domain/backup_prefs.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final Map<String, bool> _available = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probe();
      context.read<AppController>().refreshRemoteMeta();
    });
  }

  Future<void> _probe() async {
    final app = context.read<AppController>();
    for (final t in app.backupTargets) {
      final ok = await app.backupTargetAvailable(t.id);
      if (!mounted) return;
      setState(() => _available[t.id] = ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final prefs = app.backupPrefs;
    final meta = app.remoteBackupMeta;

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Backup'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 6),
              const GlassHeader(
                eyebrow: 'Your knowledge, safe',
                title: 'Backup',
              ),

              if (app.isDemo)
                const _DemoNotice()
              else ...[
                // Status card.
                GlassSection(
                  label: 'Latest backup',
                  children: [
                    GlassRow(
                      icon: prefs.frequency == BackupFrequency.off
                          ? CupertinoIcons.cloud
                          : CupertinoIcons.cloud_fill,
                      title: prefs.lastBackupAt == null
                          ? 'Not backed up yet'
                          : 'Backed up ${_when(prefs.lastBackupAt!)}',
                      subtitle: _statusSubtitle(app),
                      subtitleMaxLines: 2,
                    ),
                    _actionRow(
                      context,
                      icon: CupertinoIcons.cloud_upload_fill,
                      label: app.backupBusy ? 'Backing up…' : 'Back Up Now',
                      enabled: !app.backupBusy,
                      onTap: () => _backUpNow(context),
                    ),
                  ],
                ),

                // Destination.
                GlassSection(
                  label: 'Back up to',
                  children: [
                    for (final t in app.backupTargets)
                      GlassRow(
                        icon: t.id == 'icloud'
                            ? CupertinoIcons.cloud
                            : CupertinoIcons.cloud_download,
                        title: t.label,
                        subtitle: _availabilitySubtitle(t.id),
                        trailingCaption:
                            prefs.destinationId == t.id ? 'Selected' : null,
                        trailingCaptionColor: Palette.accent(context),
                        onTap: () =>
                            context.read<AppController>().setBackupDestination(t.id),
                      ),
                  ],
                ),

                // Frequency.
                GlassSection(
                  label: 'Auto backup',
                  children: [
                    GlassRow(
                      icon: CupertinoIcons.clock,
                      title: 'Back up automatically',
                      subtitle: prefs.frequency == BackupFrequency.off
                          ? 'Off — back up manually'
                          : '${prefs.frequency.label}, after a sync',
                      trailingCaption: 'Change',
                      trailingCaptionColor: Palette.accent(context),
                      onTap: () => _pickFrequency(context, app),
                    ),
                  ],
                ),

                // Restore.
                GlassSection(
                  label: 'Restore',
                  children: [
                    GlassRow(
                      icon: CupertinoIcons.arrow_counterclockwise_circle,
                      title: 'Restore from backup',
                      subtitle: meta == null
                          ? (app.remoteMetaChecked
                              ? 'No backup found in ${app.backupDestinationLabel}'
                              : 'Checking ${app.backupDestinationLabel}…')
                          : 'From ${meta.deviceLabel} · ${_when(meta.createdAt)}',
                      subtitleMaxLines: 2,
                      onTap: meta == null || app.backupBusy
                          ? null
                          : () => _restore(context),
                    ),
                  ],
                ),

                if (app.backupError != null)
                  Footnote(app.backupError!),
              ],

              const Footnote(
                'Backups hold only NoMail\'s insights and learned knowledge — '
                'never your mail. Google Drive backups live in a hidden '
                'app-only folder; no other app can read them.',
              ),
              const SizedBox(height: kDockClearance),
            ],
          ),
        ),
      ),
    );
  }

  String _statusSubtitle(AppController app) {
    final meta = app.remoteBackupMeta;
    final dest = app.backupDestinationLabel;
    if (meta == null) return 'Destination: $dest';
    return '$dest · ${meta.deviceLabel} · ${_size(meta.sizeBytes)}';
  }

  String _availabilitySubtitle(String id) {
    final ok = _available[id];
    if (ok == null) return 'Checking…';
    if (ok) return 'Ready';
    return id == 'icloud'
        ? 'Turn on iCloud for NoMail in Settings'
        : 'Sign in to Google to enable';
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final tint = enabled ? Palette.accent(context) : Palette.secondaryLabel(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backUpNow(BuildContext context) async {
    final app = context.read<AppController>();
    final ok = await app.backUpNow();
    if (!context.mounted) return;
    if (ok) {
      _toast(context, 'Backed up', 'Your insights and knowledge are saved to '
          '${app.backupDestinationLabel}.');
    }
    // Failure surfaces via the inline backupError footnote.
  }

  Future<void> _restore(BuildContext context) async {
    final app = context.read<AppController>();
    final meta = app.remoteBackupMeta;
    if (meta == null) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Restore from backup?'),
        content: Text(
          'This replaces the insights and learned knowledge on this device '
          'with the backup from ${meta.deviceLabel} (${_when(meta.createdAt)}).',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final outcome = await app.restoreFromBackup();
    if (!context.mounted || outcome == null) return;
    _toast(context, 'Restored', _restoreSummary(outcome));
  }

  String _restoreSummary(RestoreOutcome o) {
    final parts = <String>[
      '${o.insightCount} insight${o.insightCount == 1 ? '' : 's'}',
      if (o.learnedTypeCount > 0)
        '${o.learnedTypeCount} learned type${o.learnedTypeCount == 1 ? '' : 's'}',
    ];
    return 'Restored ${parts.join(' and ')}.';
  }

  Future<void> _pickFrequency(BuildContext context, AppController app) async {
    final chosen = await showCupertinoModalPopup<BackupFrequency>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Auto backup'),
        message: const Text(
          'A backup runs after a sync once this much time has passed.',
        ),
        actions: [
          for (final f in BackupFrequency.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, f),
              child: Text(f.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await context.read<AppController>().setBackupFrequency(chosen);
  }

  void _toast(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _when(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'am' : 'pm';
    return '${local.day} ${_months[local.month - 1]}, $hour:$minute$ampm';
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return const GlassSection(
      children: [
        GlassRow(
          icon: CupertinoIcons.info_circle,
          title: 'Backup needs a real account',
          subtitle: 'Sign in with Google to back up to iCloud or Drive.',
          subtitleMaxLines: 2,
        ),
      ],
    );
  }
}
