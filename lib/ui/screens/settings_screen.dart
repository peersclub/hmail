import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';

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
        GlassSection(
          children: [
            _profileRow(context, app),
          ],
        ),
        GlassSection(
          children: [
            if (syncing)
              _syncingRow(context, syncSubtitle)
            else
              GlassRow(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: 'Sync Now',
                subtitle: syncSubtitle,
                onTap: () => context.read<AppController>().sync(),
              ),
            GlassRow(
              icon: CupertinoIcons.sparkles,
              title: 'AI Brief',
              subtitle: app.aiLabel == 'off'
                  ? 'Off — add OPENROUTER_API_KEY to enable'
                  : app.aiLabel,
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

  /// Profile row: GlassRow layout, but the leading badge is an initial
  /// avatar rather than an icon, so it is built by hand.
  Widget _profileRow(BuildContext context, AppController app) {
    final name = app.accountName ?? 'Not signed in';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.badgeFill(context),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Palette.label(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  app.isDemo ? 'Demo mode' : (app.accountEmail ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Palette.label(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
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
