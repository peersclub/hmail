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
              GlassRow(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: 'Sync Now',
                subtitle: syncSubtitle,
                onTap: () => context.read<AppController>().sync(),
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
                      ? 'No key — add OPENROUTER_API_KEY'
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
              icon: CupertinoIcons.square_arrow_up,
              title: 'Export Insights',
              subtitle: 'Copy everything NoMail knows as JSON',
              onTap: () => _export(context, app),
            ),
            if (!syncing)
              GlassRow(
                icon: CupertinoIcons.wand_stars,
                title: 'Rescan Everything',
                subtitle: 'Clear stored insights and re-extract with AI',
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.read<AppController>().signOut(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    app.isDemo ? 'Exit Demo' : 'Sign Out',
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
    final chosen = await showCupertinoModalPopup<int>(
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
    final confirmed = await showCupertinoModalPopup<bool>(
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
          rows.add(_accountRow(
            context,
            name: account.name ?? account.email,
            detail: account.email,
            onRemove: () => _confirmRemoveAccount(context, account.email),
          ));
        }
      }
      rows.add(GlassRow(
        icon: CupertinoIcons.person_badge_plus,
        title: 'Add account',
        subtitle: 'Connect another Gmail inbox',
        onTap: () => context.read<AppController>().addAccount(),
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
    VoidCallback? onRemove,
  }) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Padding(
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
                    color: Palette.label(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
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
  }

  /// Removing an account discards its merged insights and rebuilds from the
  /// rest, so it confirms first.
  Future<void> _confirmRemoveAccount(
      BuildContext context, String email) async {
    final controller = context.read<AppController>();
    final confirmed = await showCupertinoModalPopup<bool>(
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
