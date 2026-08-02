import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ReorderableListView, DefaultMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../data/store/timeline_order_store.dart';
import '../../domain/insight.dart';
import '../../domain/insight_mapper.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';
import '../insight_card.dart';

/// Timeline — one filterable feed of every insight domain. Replaces the old
/// Packages and Reads tabs. The chip row shows a count per domain, is
/// drag-reorderable (long-press a chip and drag), and its order also drives
/// the section order in the "All" feed. Adding a new insight domain surfaces
/// here for free.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _orderStore = TimelineOrderStore();

  /// Active domain filter; null = "All".
  InsightDomain? _filter;

  /// User's saved chip order, by domain name. Present-but-unsaved domains
  /// append after these.
  List<String> _savedOrder = const [];
  bool _loadedOrder = false;

  @override
  void initState() {
    super.initState();
    _orderStore.load().then((order) {
      if (!mounted) return;
      setState(() {
        _savedOrder = order;
        _loadedOrder = true;
      });
    });
  }

  /// Present domains arranged by the user's saved order, with any new domains
  /// appended in their natural (enum) order.
  List<InsightDomain> _orderedDomains(List<InsightDomain> present) {
    final byName = {for (final d in present) d.name: d};
    final ordered = <InsightDomain>[];
    for (final name in _savedOrder) {
      final d = byName.remove(name);
      if (d != null) ordered.add(d);
    }
    for (final d in present) {
      if (byName.containsKey(d.name)) ordered.add(d);
    }
    return ordered;
  }

  void _onReorder(List<InsightDomain> current, int oldIndex, int newIndex) {
    final next = [...current];
    next.insert(newIndex, next.removeAt(oldIndex));
    HapticFeedback.mediumImpact();
    setState(() => _savedOrder = next.map((d) => d.name).toList());
    _orderStore.save(_savedOrder);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final snapshot = app.snapshot;
    final syncing = app.phase == AppPhase.syncing;

    final all = snapshotToInsights(snapshot);
    final present = presentDomains(all);
    final domains = _loadedOrder ? _orderedDomains(present) : present;

    final counts = <InsightDomain, int>{};
    for (final i in all) {
      counts[i.domain] = (counts[i.domain] ?? 0) + 1;
    }

    // A filter can go stale if its domain empties out on the next sync.
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
                    counts: counts,
                    total: all.length,
                    selected: activeFilter,
                    onSelect: (domain) {
                      HapticFeedback.selectionClick();
                      setState(() => _filter = domain);
                    },
                    onReorder: (o, n) => _onReorder(domains, o, n),
                  ),
                // Breathing room so the first card never crowds the chips.
                const SizedBox(height: 6),
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
                else if (shown.isEmpty)
                  // A selected chip whose domain has emptied out: name what
                  // belongs here instead of rendering a blank list.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(44, 56, 44, 0),
                    child: Text(
                      _domainEmptyLine(activeFilter),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Palette.secondaryLabel(context),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _DomainSection(insights: shown),
                  ),
                const SizedBox(height: kDockClearance),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One short line per domain for the filtered-empty state — says what the
/// domain collects so an empty filter still teaches what belongs there.
String _domainEmptyLine(InsightDomain domain) => switch (domain) {
      InsightDomain.security =>
        'No security alerts right now — sign-in warnings and account alerts appear here.',
      InsightDomain.money =>
        'No money items right now — bills, renewals and refunds appear here.',
      InsightDomain.commerce =>
        'No deliveries right now — parcels and return windows appear here.',
      InsightDomain.travel =>
        'No trips right now — flights, trains and hotel bookings appear here.',
      InsightDomain.work =>
        'No work items right now — meetings and calendar invites appear here.',
      InsightDomain.content =>
        'No reads right now — newsletters and articles appear here.',
      InsightDomain.personal =>
        'Nothing personal right now — invitations and personal follow-ups appear here.',
      InsightDomain.government =>
        'No identity items right now — government and ID paperwork appears here.',
    };

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

/// Horizontal chip row: a fixed "All" chip plus one draggable chip per domain,
/// each showing its count. Long-press a domain chip to drag it into a new
/// position; tap to filter.
class _FilterChips extends StatelessWidget {
  final List<InsightDomain> domains;
  final Map<InsightDomain, int> counts;
  final int total;
  final InsightDomain? selected;
  final ValueChanged<InsightDomain?> onSelect;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _FilterChips({
    required this.domains,
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 20),
          _Chip(
            label: 'All',
            count: total,
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Localizations.override(
              context: context,
              delegates: const [DefaultMaterialLocalizations.delegate],
              child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(right: 20),
              onReorderItem: onReorder,
              proxyDecorator: (child, index, animation) => Transform.scale(
                scale: 1.06,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x33000000),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
              itemCount: domains.length,
              itemBuilder: (context, i) {
                final domain = domains[i];
                return Padding(
                  key: ValueKey(domain.name),
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDelayedDragStartListener(
                    index: i,
                    child: _Chip(
                      label: domain.label,
                      count: counts[domain] ?? 0,
                      active: selected == domain,
                      onTap: () => onSelect(domain),
                    ),
                  ),
                );
              },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = active
        ? Palette.onAccent(context)
        : Palette.label(context);
    // Restored: no alpha stacked on an already-reduced secondary gray.
    final countColor = active
        ? Palette.onAccent(context).withValues(alpha: 0.8)
        : Palette.secondaryLabel(context);
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $count',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 44pt hit target around the 34pt visual pill.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Container(
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color:
                  active ? Palette.accent(context) : Palette.badgeFill(context),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· $count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: countColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
