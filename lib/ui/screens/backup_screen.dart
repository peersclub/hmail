/// Backup & Restore — the "your knowledge is safe" surface.
///
/// Journey rules this screen lives by:
///  1. Progress, success, and failure render *on the control the user tapped*
///     — an inline line right under Back Up Now / Restore. Never a footnote
///     somewhere else, never a toast over the buttons.
///  2. Every failure names its cause and its recovery (the messages come from
///     the target layer, which maps Google's errors to human ones).
///  3. Preconditions become steps, not failures: demo mode shows the path to
///     a real account instead of letting a doomed backup be attempted.
///  4. The first backup sets expectations: Google will ask once for a hidden
///     app-only folder — the screen says so before the sheet appears.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
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
      // Silent — shows what's already in the cloud without any prompt.
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

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Backup'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: ReadableWidth(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 10),
                if (app.isDemo)
                  ..._demoJourney(context)
                else ...[
                  _backupSection(context, app),
                  _destinationSection(context, app),
                  _frequencySection(context, app),
                  _restoreSection(context, app),
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
      ),
    );
  }

  // ── Demo: show the path, not a dead end ─────────────────────────────────

  List<Widget> _demoJourney(BuildContext context) => [
        GlassSection(
          children: [
            const GlassRow(
              icon: CupertinoIcons.cloud,
              title: 'Backup protects your insights',
              subtitle: 'Everything NoMail learns moves with you to a new '
                  'phone — bills, deliveries, and its learned knowledge.',
              subtitleMaxLines: 3,
            ),
            const GlassRow(
              icon: CupertinoIcons.person_crop_circle_badge_exclam,
              title: 'Demo data isn\'t backed up',
              subtitle: 'You\'re exploring with sample data. Connect your '
                  'Google account to back up for real.',
              subtitleMaxLines: 3,
            ),
            _actionRow(
              context,
              icon: CupertinoIcons.arrow_right_circle_fill,
              label: 'Exit Demo & Sign In',
              busy: false,
              enabled: true,
              onTap: () {
                final app = context.read<AppController>();
                Navigator.of(context).pop();
                app.signOut(); // demo exit → sign-in screen
              },
            ),
          ],
        ),
      ];

  // ── Backup: status + action + inline result, one card ───────────────────

  Widget _backupSection(BuildContext context, AppController app) {
    final prefs = app.backupPrefs;
    final meta = app.remoteBackupMeta;
    final busy = app.backupActivity == BackupActivity.backingUp;
    final never = prefs.lastBackupAt == null;

    final String subtitle;
    if (never) {
      subtitle = 'Keeps your insights and NoMail\'s learned knowledge safe '
          'if you lose or switch phones.';
    } else {
      subtitle = [
        app.backupDestinationLabel,
        if (meta != null) meta.deviceLabel,
        if (meta != null) _size(meta.sizeBytes),
      ].join(' · ');
    }

    return GlassSection(
      label: 'Latest backup',
      children: [
        GlassRow(
          icon: never ? CupertinoIcons.cloud : CupertinoIcons.cloud_fill,
          title: never
              ? 'Not backed up yet'
              : 'Backed up ${_when(prefs.lastBackupAt!)}',
          subtitle: subtitle,
          subtitleMaxLines: 3,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _actionRow(
              context,
              icon: CupertinoIcons.cloud_upload_fill,
              label: busy ? 'Backing up…' : 'Back Up Now',
              busy: busy,
              enabled: !app.backupBusy,
              onTap: () async {
                // Success gets a tactile confirmation (HIG: haptics for
                // completed important actions, sparingly).
                final ok = await context.read<AppController>().backUpNow();
                if (ok) HapticFeedback.mediumImpact();
              },
            ),
            ..._resultLines(
              context,
              app,
              scope: BackupErrorScope.backup,
              // Set the consent expectation before Google's sheet appears.
              hint: never && !busy
                  ? 'Google will ask once to let NoMail use its own private '
                      'folder — nothing else in your Drive.'
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  // ── Destination ──────────────────────────────────────────────────────────

  Widget _destinationSection(BuildContext context, AppController app) {
    final selected = app.backupPrefs.destinationId;
    return GlassSection(
      label: 'Back up to',
      children: [
        for (final t in app.backupTargets)
          _destinationRow(context, app, id: t.id, label: t.label,
              selected: selected == t.id),
      ],
    );
  }

  Widget _destinationRow(
    BuildContext context,
    AppController app, {
    required String id,
    required String label,
    required bool selected,
  }) {
    final ok = _available[id];
    final isICloud = id == 'icloud';

    final String subtitle;
    if (ok == null) {
      subtitle = 'Checking…';
    } else if (isICloud && !ok) {
      // Honest: there is no switch the user can flip for this build.
      subtitle = 'Not available in this build yet';
    } else if (!ok) {
      subtitle = 'Connect a Google account to enable';
    } else {
      subtitle = isICloud
          ? 'Stored in your iCloud'
          : 'Hidden app-only folder in your Drive';
    }

    final selectable = ok == true && !app.backupBusy;
    return GlassRow(
      icon: isICloud ? CupertinoIcons.cloud : CupertinoIcons.cloud_download,
      iconTint: ok == false ? Palette.secondaryLabel(context) : null,
      title: label,
      subtitle: subtitle,
      trailing: selected ? '✓' : null,
      onTap: selectable
          ? () => context.read<AppController>().setBackupDestination(id)
          : null,
    );
  }

  // ── Frequency ────────────────────────────────────────────────────────────

  Widget _frequencySection(BuildContext context, AppController app) {
    final freq = app.backupPrefs.frequency;
    return GlassSection(
      label: 'Auto backup',
      children: [
        GlassRow(
          icon: CupertinoIcons.clock,
          title: 'Back up automatically',
          subtitle: freq.interval == null
              ? 'Off — back up manually'
              : '${freq.label} · runs after a sync once due',
          trailingCaption: 'Change',
          trailingCaptionColor: Palette.accent(context),
          onTap: app.backupBusy ? null : () => _pickFrequency(context, app),
        ),
      ],
    );
  }

  // ── Restore: check → confirm → apply, all visible ────────────────────────

  Widget _restoreSection(BuildContext context, AppController app) {
    final meta = app.remoteBackupMeta;
    final checking = app.backupActivity == BackupActivity.checking;
    final restoring = app.backupActivity == BackupActivity.restoring;

    final String label;
    if (checking) {
      label = 'Checking ${app.backupDestinationLabel}…';
    } else if (restoring) {
      label = 'Restoring…';
    } else {
      label = 'Restore from backup';
    }

    final String subtitle;
    if (meta != null) {
      subtitle = 'From ${meta.deviceLabel} · ${_when(meta.createdAt)}'
          '${meta.insightCount > 0 ? ' · ${meta.insightCount} insights' : ''}';
    } else {
      subtitle =
          'Fetches your latest backup from ${app.backupDestinationLabel}';
    }

    return GlassSection(
      label: 'Restore',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassRow(
              icon: CupertinoIcons.arrow_counterclockwise_circle,
              title: label,
              subtitle: subtitle,
              subtitleMaxLines: 2,
              onTap: app.backupBusy ? null : () => _restoreFlow(context),
            ),
            if (checking || restoring)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CupertinoActivityIndicator(),
              ),
            ..._resultLines(context, app, scope: BackupErrorScope.restore),
          ],
        ),
      ],
    );
  }

  Future<void> _restoreFlow(BuildContext context) async {
    final app = context.read<AppController>();
    // Step 1: fetch (may show Google's consent sheet — the user asked).
    final meta = await app.prepareRestore();
    if (meta == null || !context.mounted) return; // error line already shown

    // Step 2: confirm with the backup's real contents — a destructive act
    // deserves a modal, and the user deserves to know what they're applying.
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          '\n${meta.deviceLabel} · ${_when(meta.createdAt)}\n'
          '${meta.insightCount} insights'
          '${meta.learnedTypeCount > 0 ? ' · ${meta.learnedTypeCount} learned types' : ''}'
          ' · ${_size(meta.sizeBytes)}\n\n'
          'This replaces the insights and learned knowledge currently on '
          'this device.',
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
    if (!context.mounted) return;
    if (confirmed != true) {
      app.cancelRestore();
      return;
    }
    // Step 3: apply — result renders inline under this row.
    final outcome = await app.confirmRestore();
    if (outcome != null) HapticFeedback.mediumImpact();
  }

  // ── Shared pieces ────────────────────────────────────────────────────────

  /// Inline result directly under an action: the error or success for [scope],
  /// or a quiet expectation-setting hint when there's nothing to report.
  List<Widget> _resultLines(
    BuildContext context,
    AppController app, {
    required BackupErrorScope scope,
    String? hint,
  }) {
    final error = app.backupErrorScope == scope ? app.backupError : null;
    final notice = app.backupNoticeScope == scope ? app.backupNotice : null;
    if (error != null) {
      return [
        _inlineLine(context,
            icon: CupertinoIcons.exclamationmark_circle_fill,
            text: error,
            color: Palette.destructive(context)),
      ];
    }
    if (notice != null) {
      return [
        _inlineLine(context,
            icon: CupertinoIcons.checkmark_circle_fill,
            text: notice,
            color: Palette.accent(context)),
      ];
    }
    if (hint != null) {
      return [
        _inlineLine(context,
            icon: CupertinoIcons.info_circle,
            text: hint,
            color: Palette.secondaryLabel(context)),
      ];
    }
    return const [];
  }

  Widget _inlineLine(BuildContext context,
      {required IconData icon, required String text, required Color color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool busy,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final tint =
        enabled ? Palette.accent(context) : Palette.secondaryLabel(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          if (busy)
            const CupertinoActivityIndicator(radius: 9)
          else
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
    );
    if (!enabled || busy) return content;
    return PressableRow(onTap: onTap, child: content);
  }

  Future<void> _pickFrequency(BuildContext context, AppController app) async {
    final chosen = await showSheet<BackupFrequency>(
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
