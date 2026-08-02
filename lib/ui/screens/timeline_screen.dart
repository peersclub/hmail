import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/insight.dart';
import '../../domain/insight_mapper.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../insight_card.dart';

/// Timeline — one filterable feed of every insight domain. Replaces the old
/// Packages and Reads tabs: instead of a tab per category, a chip row filters
/// a single ranked stream. Adding a new insight domain surfaces here for free.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  /// The active domain filter; null means "All".
  InsightDomain? _filter;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final snapshot = app.snapshot;
    final syncing = app.phase == AppPhase.syncing;

    final all = snapshotToInsights(snapshot);
    final domains = presentDomains(all);

    // A filter can go stale if the underlying data changes (a domain empties
    // out on the next sync). Fall back to All rather than showing nothing.
    final activeFilter =
        (_filter != null && domains.contains(_filter)) ? _filter : null;

    final shown = rankInsights(
      all.where((i) => activeFilter == null || i.domain == activeFilter).toList(),
    );

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: MediaQuery.paddingOf(context).top + 6),
                GlassHeader(
                  title: 'Timeline',
                  eyebrow: all.isEmpty
                      ? 'Everything from your inbox'
                      : '${all.length} insights',
                ),
                if (domains.isNotEmpty)
                  _FilterChips(
                    domains: domains,
                    selected: activeFilter,
                    onSelect: (domain) {
                      HapticFeedback.selectionClick();
                      setState(() => _filter = domain);
                    },
                  ),
                if (all.isEmpty)
                  GlassEmptyState(
                    icon: CupertinoIcons.tray,
                    title: 'Nothing Yet',
                    caption: syncing
                        ? 'Scanning your inbox…'
                        : 'Insights from every corner of your inbox collect here.',
                  )
                else if (activeFilter == null)
                  for (final domain in domains)
                    _DomainSection(
                      label: domain.label,
                      insights: [
                        for (final i in shown)
                          if (i.domain == domain) i,
                      ],
                    )
                else
                  _DomainSection(insights: shown),
                const SizedBox(height: kDockClearance),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One glass section of insight rows. Unlabeled when a specific filter is
/// active (the chip already names the domain), labeled when grouping All.
class _DomainSection extends StatelessWidget {
  final String? label;
  final List<Insight> insights;

  const _DomainSection({this.label, required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return GlassSection(
      label: label,
      children: [for (final i in insights) InsightCard(insight: i)],
    );
  }
}

/// Horizontal pill row: "All" plus one chip per present domain. Selected chip
/// fills with the ink accent; the rest are quiet glass.
class _FilterChips extends StatelessWidget {
  final List<InsightDomain> domains;
  final InsightDomain? selected;
  final ValueChanged<InsightDomain?> onSelect;

  const _FilterChips({
    required this.domains,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _Chip(
            label: 'All',
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final domain in domains) ...[
            const SizedBox(width: 8),
            _Chip(
              label: domain.label,
              active: selected == domain,
              onTap: () => onSelect(domain),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? Palette.accent(context) : Palette.badgeFill(context),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: active
                ? Palette.onAccent(context)
                : Palette.secondaryLabel(context),
          ),
        ),
      ),
    );
  }
}
