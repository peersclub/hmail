import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/sync_report.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';
import 'ai_screen.dart';
import 'backup_screen.dart';
import 'corrections_screen.dart';
import 'knowledge_screen.dart';
import 'processing_screen.dart';
import 'scan_screen.dart';

/// Settings tab. Rendered inside the app shell (backdrop + dock supplied),
/// so this is scroll content only.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final syncing = app.phase == AppPhase.syncing;

    final syncSubtitle = app.snapshot.lastSyncedAt == null
        ? 'Never synced'
        : '${formatDay(app.snapshot.lastSyncedAt!)} · '
            '${app.snapshot.emailsScanned} emails scanned';

    // Sync errors render under the Data section whose action produced them;
    // account actions narrate themselves inside the Accounts section.
    final err = app.error;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + 6),
        const GlassHeader(eyebrow: 'Account & privacy', title: 'Settings'),
        _accountsSection(context, app),
        GlassSection(
          label: 'Data',
          children: [
            if (syncing)
              _syncingRow(context, app.stage.label)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassRow(
                    icon: CupertinoIcons.arrow_2_circlepath,
                    title: 'Sync Now',
                    subtitle: syncSubtitle,
                    onTap: () => context.read<AppController>().sync(),
                  ),
                  // The failure lands right under the row that can retry it.
                  if (err != null)
                    _inlineError(context, '$err Tap Sync Now to retry.'),
                ],
              ),
            GlassRow(
              icon: CupertinoIcons.slider_horizontal_3,
              title: 'Scanning',
              subtitle: app.settings.describeScope,
              subtitleMaxLines: 2,
              onTap: () => _push(context, const ScanScreen()),
            ),
            GlassRow(
              icon: CupertinoIcons.list_bullet_below_rectangle,
              title: 'Processing',
              subtitle: app.lastReport.headline,
              subtitleMaxLines: 2,
              onTap: () => _push(context, const ProcessingScreen()),
            ),
          ],
        ),
        GlassSection(
          label: 'Intelligence',
          children: [
            GlassRow(
              icon: CupertinoIcons.sparkles,
              title: 'AI',
              subtitle: !app.settings.aiEnabled
                  ? 'Off — rules only'
                  : (app.aiLabel == 'off'
                      ? 'No key — tap to add your OpenRouter key'
                      : app.aiLabel),
              subtitleMaxLines: 2,
              onTap: () => _push(context, const AiScreen()),
            ),
            GlassRow(
              icon: CupertinoIcons.lightbulb,
              title: 'Knowledge',
              subtitle: app.playbook.isEmpty
                  ? 'Nothing learned yet'
                  : '${app.playbook.length} thing'
                      '${app.playbook.length == 1 ? '' : 's'} NoMail taught itself',
              subtitleMaxLines: 2,
              onTap: () => _push(context, const KnowledgeScreen()),
            ),
            GlassRow(
              icon: CupertinoIcons.hand_thumbsdown,
              title: 'Corrections',
              subtitle: app.ignores.isEmpty
                  ? 'Nothing hidden — tap "Not a bill" on any insight'
                  : '${app.ignores.length} thing'
                      '${app.ignores.length == 1 ? '' : 's'} hidden from your '
                      'insights',
              subtitleMaxLines: 2,
              onTap: () => _push(context, const CorrectionsScreen()),
            ),
            GlassRow(
              icon: CupertinoIcons.bell,
              title: 'Daily Brief',
              subtitle: 'Every day at ${_hourLabel(app.settings.briefHour)}',
              trailingCaption: 'Change',
              trailingCaptionColor: Palette.accent(context),
              onTap: () => _pickBriefHour(context, app),
            ),
          ],
        ),
        GlassSection(
          label: 'Your data',
          children: [
            GlassRow(
              icon: CupertinoIcons.cloud,
              title: 'Backup',
              subtitle: _backupSubtitle(app),
              subtitleMaxLines: 2,
              onTap: () => _push(context, const BackupScreen()),
            ),
            GlassRow(
              icon: CupertinoIcons.square_arrow_up,
              title: 'Export Insights',
              subtitle: 'Copy everything NoMail knows as JSON',
              onTap: () => _export(context, app),
            ),
            if (!syncing)
              GlassRow(
                icon: CupertinoIcons.wand_stars,
                title: 'Rescan Everything',
                // Don't promise an AI pass that won't run.
                subtitle: app.settings.aiEnabled && app.aiLabel != 'off'
                    ? 'Clear stored insights and re-extract with AI'
                    : 'Clear stored insights and re-extract',
                onTap: () => _confirmRescan(context),
              ),
          ],
        ),
        const Footnote(
          'Read-only Gmail scope. Insights are stored only on this device. '
          'NoMail cannot send, move, or delete mail.',
        ),
        GlassSection(
          children: [
            PressableRow(
              onTap: () => context.read<AppController>().replayOnboarding(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Replay intro',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Palette.label(context),
                    ),
                  ),
                ),
              ),
            ),
            PressableRow(
              onTap: () => _confirmSignOut(context, app),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    app.isDemo ? 'Exit Demo' : 'Sign Out',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      // Not destructive any more — signing out keeps your
                      // insights. The red is spent on the row below, which is
                      // the one that actually erases something.
                      color: Palette.label(context),
                    ),
                  ),
                ),
              ),
            ),
            if (!app.isDemo)
              PressableRow(
                onTap: () => _confirmDeleteData(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Delete data on this device',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Palette.destructive(context),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Footnote('NoMail — your inbox, minus the inbox.'),
        const SizedBox(height: kDockClearance),
      ],
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context, rootNavigator: true)
        .push(CupertinoPageRoute<void>(builder: (_) => screen));
  }

  /// Backup row subtitle tells the user where they are in the journey, not
  /// just a state dump.
  static String _backupSubtitle(AppController app) {
    if (app.isDemo) return 'Needs a real account';
    final last = app.backupPrefs.lastBackupAt;
    if (last == null) return 'Not set up yet';
    final freq = app.backupPrefs.frequency;
    return [
      formatDay(last),
      app.backupDestinationLabel,
      if (freq.interval != null) freq.label,
    ].join(' · ');
  }

  /// Inline error INSIDE a glass card, directly under the row that failed.
  Widget _inlineError(BuildContext context, String message) {
    final color = Palette.destructive(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(CupertinoIcons.exclamationmark_circle_fill,
                size: 14, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }


  /// Signing out clears the local insight cache — that deserves the same
  /// confirm the less-destructive account removal already gets.
  Future<void> _confirmSignOut(BuildContext context, AppController app) async {
    final isDemo = app.isDemo;
    final confirmed = await showSheet<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(isDemo ? 'Exit demo?' : 'Sign out?'),
        message: Text(
          isDemo
              ? 'Sample data is cleared and you return to sign-in. '
                  'Tap Replay intro there to see the carousel again.'
              : 'Your insights stay on this device and come back when you '
                  'sign in with this account again. Your mail is untouched.',
        ),
        actions: [
          CupertinoActionSheetAction(
            // No longer destructive: nothing is erased. "Delete data on this
            // device" is the row for that, and keeping the red exclusive to it
            // is what makes the difference legible.
            onPressed: () => Navigator.pop(sheetContext, true),
            child: Text(isDemo ? 'Exit Demo' : 'Sign Out'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppController>().signOut();
    }
  }

  /// The genuinely destructive one, so it says exactly what goes and what
  /// stays. "Your mail is untouched" is the sentence people need most here —
  /// a delete button in an email app reads as deleting email.
  Future<void> _confirmDeleteData(BuildContext context) async {
    final confirmed = await showSheet<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Delete data on this device?'),
        message: const Text(
          'Erases your insights, learned recipes and corrections, and signs '
          'you out. Your mail is untouched — nothing in Gmail changes. This '
          'cannot be undone on this device; a cloud backup, if you have one, '
          'can still restore it.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('Delete Data'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppController>().deleteLocalData();
    }
  }

  static String _hourLabel(int hour) {
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display${hour < 12 ? 'am' : 'pm'}';
  }

  /// Export puts the user's insights on the clipboard as JSON — the cheapest
  /// honest answer to "is my data locked in?".
  Future<void> _export(BuildContext context, AppController app) async {
    final payload = const JsonEncoder.withIndent('  ')
        .convert(app.snapshot.toJson());
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Copied'),
        content: Text(
          '${app.snapshot.subscriptions.length + app.snapshot.bills.length + app.snapshot.deliveries.length + app.snapshot.events.length} '
          'insights copied to the clipboard as JSON.',
        ),
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

  Future<void> _pickBriefHour(BuildContext context, AppController app) async {
    const hours = [6, 7, 8, 9, 10, 20];
    final chosen = await showSheet<int>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Daily brief'),
        message: const Text('When should the summary arrive?'),
        actions: [
          for (final hour in hours)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, hour),
              child: Text(_hourLabel(hour)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (chosen != null) {
      await app.updateSettings(app.settings.copyWith(briefHour: chosen));
    }
  }

  /// Rescan discards stored insights, so it asks first — a slow rebuild the
  /// user didn't expect feels like data loss.
  Future<void> _confirmRescan(BuildContext context) async {
    final controller = context.read<AppController>();
    final confirmed = await showSheet<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Rescan everything?'),
        message: const Text(
          'Stored insights are discarded and rebuilt from your mail. '
          'The AI pass re-checks every result and fixes wrong ones.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('Rescan'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed == true) await controller.rescan();
  }

  /// Accounts section: one row per connected Gmail account (initial-circle
  /// avatar + email, each removable), plus an "Add account" row. In demo mode
  /// it shows a single read-only demo row.
  Widget _accountsSection(BuildContext context, AppController app) {
    final rows = <Widget>[];

    if (app.isDemo) {
      rows.add(_accountRow(
        context,
        name: app.accountName ?? 'Demo',
        detail: 'Demo mode',
      ));
    } else {
      final accounts = app.accounts;
      if (accounts.isEmpty) {
        rows.add(_accountRow(
          context,
          name: 'Not signed in',
          detail: 'Add a Gmail account below',
        ));
      } else {
        for (final account in accounts) {
          final issue = app.accountSyncIssues[account.email];
          rows.add(_accountRow(
            context,
            name: account.name ?? account.email,
            // Priority: a live problem beats the resting email line, and a
            // lost session beats both — each states its own next step.
            detail: !account.connected
                ? 'Session ended — tap to reconnect'
                : (issue ?? account.email),
            detailColor: (!account.connected || issue != null)
                ? Palette.destructive(context)
                : null,
            dimmed: !account.connected,
            onTap: account.connected
                ? null
                : () =>
                    context.read<AppController>().reconnectAccount(account.email),
            onRemove: () => _confirmRemoveAccount(context, account.email),
          ));
        }
      }
      // In-flow narration for the last account action, under the rows it
      // concerns — connected, already-connected guidance, or the failure.
      if (app.accountsError != null) {
        rows.add(_inlineError(context, app.accountsError!));
      } else if (app.accountsNotice != null) {
        rows.add(_inlineNotice(context, app.accountsNotice!));
      }
      rows.add(GlassRow(
        icon: CupertinoIcons.person_badge_plus,
        title: 'Add account',
        subtitle: 'Connect another Gmail inbox',
        onTap: () async {
          final app = context.read<AppController>();
          await app.addAccount();
          // Only a *new* connection earns the tap on the wrist.
          if (app.accountsError == null &&
              (app.accountsNotice?.startsWith('Connected') ?? false)) {
            HapticFeedback.lightImpact();
          }
        },
      ));
    }

    return GlassSection(label: 'Accounts', children: rows);
  }

  /// A connected-account row: GlassRow layout, but the leading badge is an
  /// initial avatar rather than an icon (so it is built by hand) and the
  /// trailing affordance is a Remove button when [onRemove] is given.
  Widget _accountRow(
    BuildContext context, {
    required String name,
    required String detail,
    Color? detailColor,
    bool dimmed = false,
    VoidCallback? onTap,
    VoidCallback? onRemove,
  }) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.badgeFill(context),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Palette.secondaryLabel(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    letterSpacing: -0.4,
                    color: dimmed
                        ? Palette.secondaryLabel(context)
                        : Palette.label(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: detailColor ?? Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: onRemove,
              child: Text(
                'Remove',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Palette.destructive(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return PressableRow(onTap: onTap, child: row);
  }

  /// A quiet in-flow confirmation under the account rows (accent ✓).
  Widget _inlineNotice(BuildContext context, String message) {
    final color = Palette.accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(CupertinoIcons.checkmark_circle_fill,
                size: 14, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Removing an account discards its merged insights and rebuilds from the
  /// rest, so it confirms first.
  Future<void> _confirmRemoveAccount(
      BuildContext context, String email) async {
    final controller = context.read<AppController>();
    final confirmed = await showSheet<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('Remove $email?'),
        message: const Text(
          'Its insights are cleared and NoMail rebuilds from your remaining '
          'accounts. Removing the last account signs you out.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('Remove'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed == true) await controller.removeAccount(email);
  }

  /// Sync row while a sync is running: mirrors GlassRow's layout with a
  /// trailing activity indicator (GlassRow only takes string trailings).
  Widget _syncingRow(BuildContext context, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          const IconBadge(CupertinoIcons.arrow_2_circlepath),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    letterSpacing: -0.4,
                    color: Palette.label(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const CupertinoActivityIndicator(),
        ],
      ),
    );
  }
}
