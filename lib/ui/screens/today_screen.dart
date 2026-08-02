import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/insight.dart';
import '../../domain/insight_mapper.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';
import '../insight_card.dart';

/// Today — the morning-glance screen. Brief, counts, and everything that
/// needs the user's attention in the next ten days.
class TodayScreen extends StatelessWidget {
  final void Function(int tab)? onNavigate;

  const TodayScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final snapshot = app.snapshot;

    // One ranked, cross-domain feed. Today shows only what's pressing —
    // imminent items as "Needs attention", near items as "Coming up".
    // Everything ambient (new reads, far-off renewals) lives in Timeline.
    final insights = rankInsights(snapshotToInsights(snapshot));
    final attention =
        insights.where((i) => i.urgency == UrgencyTier.imminent).toList();
    final comingUp =
        insights.where((i) => i.urgency == UrgencyTier.near).toList();
    final dueCount = snapshot.unpaidUpcoming
        .where((b) => b.isOverdue || b.dueWithin(const Duration(days: 10)))
        .length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: MediaQuery.paddingOf(context).top + 6),
              GlassHeader(
                eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
                title: 'Today',
                trailing: app.phase == AppPhase.syncing
                    ? const CupertinoActivityIndicator()
                    : _accountBubble(context, app),
              ),
            ],
          ),
        ),
        CupertinoSliverRefreshControl(
          onRefresh: () => context.read<AppController>().sync(),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (app.isDemo)
                const Footnote(
                    'Demo data — sign in with Google for your own insights.'),
              if (app.showMoneyShot) _moneyShotCard(context, app),
              if (snapshot.brief != null)
                _briefCard(context, snapshot.brief!,
                    ai: app.aiLabel != 'off' && !app.isDemo),
              _statStrip(context, snapshot, dueCount),
              if (attention.isNotEmpty)
                GlassSection(
                  label: 'Needs attention',
                  children: [
                    for (final i in attention) InsightCard(insight: i),
                  ],
                ),
              if (comingUp.isNotEmpty)
                GlassSection(
                  label: 'Coming up',
                  children: [
                    for (final i in comingUp) InsightCard(insight: i),
                  ],
                ),
              if (snapshot.isEmpty)
                GlassEmptyState(
                  icon: CupertinoIcons.sparkles,
                  title: 'No Insights Yet',
                  caption: app.phase == AppPhase.syncing
                      ? 'Scanning your Gmail…'
                      : 'Pull down to scan your Gmail for bills, subscriptions and deliveries.',
                )
              else if (attention.isEmpty && comingUp.isEmpty)
                GlassSection(
                  children: [
                    GlassRow(
                      icon: CupertinoIcons.checkmark_circle,
                      title: 'All clear',
                      subtitle:
                          'Nothing pressing today. Browse everything in Timeline.',
                      onTap: () => onNavigate?.call(2),
                    ),
                  ],
                ),
              if (snapshot.lastSyncedAt != null)
                Footnote(
                    'Synced ${formatDay(snapshot.lastSyncedAt!)} · ${snapshot.emailsScanned} emails scanned'),
              if (app.error != null) Footnote(app.error!),
              const SizedBox(height: kDockClearance),
            ],
          ),
        ),
      ],
    );
  }




  Widget _accountBubble(BuildContext context, AppController app) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Palette.badgeFill(context),
      ),
      child: Center(
        child: Text(
          (app.accountName ?? '?').substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Palette.secondaryLabel(context),
          ),
        ),
      ),
    );
  }

  /// First-scan celebration: what the pipeline just found hiding in the
  /// inbox. Shown once per fresh account, dismissed by hand.
  Widget _moneyShotCard(BuildContext context, AppController app) {
    final stats = app.backfillStats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(CupertinoIcons.sparkles,
                tint: Palette.accent(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hiding in your inbox',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Palette.accent(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats.headline,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      letterSpacing: -0.2,
                      color: Palette.label(context),
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(4),
              onPressed: app.dismissMoneyShot,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 22,
                color: Palette.tertiaryLabel(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _briefCard(BuildContext context, DailyBrief brief,
      {required bool ai}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              brief.headline,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                height: 1.3,
                color: Palette.label(context),
              ),
            ),
            const SizedBox(height: 4),
            for (final bullet in brief.bullets) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Palette.tertiaryLabel(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Palette.secondaryLabel(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(CupertinoIcons.sparkles,
                    size: 13, color: Palette.tertiaryLabel(context)),
                const SizedBox(width: 5),
                Text(
                  ai ? 'AI Brief' : 'Daily brief',
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.tertiaryLabel(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statStrip(
      BuildContext context, InsightSnapshot snapshot, int dueCount) {
    Widget stat(String value, String caption, int tab) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onNavigate?.call(tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Palette.label(context),
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget hairline() =>
        Container(width: 0.7, height: 28, color: Palette.hairline(context));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GlassCard(
        child: Row(
          children: [
            stat('$dueCount', 'Due Soon', 1),
            hairline(),
            stat('${snapshot.subscriptions.length}', 'Subscriptions', 1),
            hairline(),
            stat('${snapshot.activeDeliveries.length}', 'Arriving', 2),
          ],
        ),
      ),
    );
  }
}
