import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/brand_icons.dart';
import '../../core/palette.dart';
import '../../domain/actions.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../action_sheet.dart';
import '../format.dart';
import '../glass/glass.dart';
import '../widgets/journey_states.dart';

/// Money tab: recurring spend hero with a monochrome share bar, then
/// subscriptions and upcoming bills. Scroll content only — the shell owns
/// the background and floating dock.
class MoneyScreen extends StatelessWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final snapshot = app.snapshot;

    final currency = snapshot.dominantCurrency;
    final dominantSubs = snapshot.subscriptions
        .where((s) => s.currency == currency)
        .toList()
      ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
    final monthlyTotal =
        dominantSubs.fold(0.0, (sum, s) => sum + s.monthlyAmount);
    final otherCurrencies = Map.of(snapshot.recurringByCurrency)
      ..remove(currency);

    final allSubs = snapshot.subscriptions.toList()
      ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
    final bills = snapshot.unpaidUpcoming;
    final isEmpty = allSubs.isEmpty && bills.isEmpty;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + 6),
        GlassHeader(
          eyebrow: 'Recurring & bills',
          title: 'Money',
          // Same live-scan signal as Today — a tab must never look idle
          // while the pipeline is running.
          trailing:
              app.phase == AppPhase.syncing ? const SyncBusyBadge() : null,
        ),
        if (isEmpty) ...[
          const GlassEmptyState(
            icon: CupertinoIcons.creditcard,
            title: 'No Money Insights Yet',
            caption:
                'Bills due, subscription renewals and refunds found in your email appear here.',
          ),
          // Journey states: narrate a running scan; offer the scan when one
          // has never run; stay quiet when a scan simply found no money.
          if (app.phase == AppPhase.syncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 44),
              child: BusyLine(app.activityLine),
            )
          else if (snapshot.lastSyncedAt == null && !app.isDemo)
            const ScanActionButton(),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Hero(
              currency: currency,
              subscriptions: dominantSubs,
              monthlyTotal: monthlyTotal,
              otherCurrencies: otherCurrencies,
            ),
          ),
          if (allSubs.isNotEmpty)
            GlassSection(
              label: 'Subscriptions',
              children: [
                for (final sub in allSubs)
                  GlassRow(
                    icon: BrandIcons.forName(sub.service) ??
                        CupertinoIcons.arrow_2_circlepath,
                    title: sub.service,
                    subtitle: _subscriptionSubtitle(sub),
                    trailing:
                        '${formatMoney(sub.monthlyAmount, sub.currency)}/mo',
                    onTap: () => showInsightActions(
                      context,
                      title: sub.service,
                      message: _attribution(context, sub.sourceEmailId),
                      actions: actionsForSubscription(sub),
                    ),
                  ),
              ],
            ),
          if (bills.isNotEmpty)
            GlassSection(
              label: 'Bills',
              children: [
                for (final bill in bills)
                  GlassRow(
                    icon: CupertinoIcons.doc_text_fill,
                    title: bill.issuer,
                    trailing: formatMoney(bill.amount, bill.currency),
                    trailingCaption: bill.isOverdue
                        ? 'Overdue'
                        : 'Due ${formatDay(bill.dueDate!)}',
                    trailingCaptionColor: Palette.urgency(
                      context,
                      bill.dueDate,
                      overdue: bill.isOverdue,
                    ),
                    trailingCaptionPill: bill.isOverdue,
                    onTap: () => showInsightActions(
                      context,
                      title: bill.issuer,
                      message: [
                        formatMoney(bill.amount, bill.currency),
                        if (_attribution(context, bill.sourceEmailId)
                            case final String from)
                          from,
                      ].join(' · '),
                      actions: actionsForBill(bill),
                    ),
                  ),
              ],
            ),
        ],
        const SizedBox(height: kDockClearance),
      ],
    );
  }

  String? _subscriptionSubtitle(Subscription sub) {
    final parts = [
      if (sub.cadence == Cadence.yearly)
        'Yearly · ${formatMoney(sub.amount, sub.currency)}',
      if (sub.nextRenewal != null) 'Renews ${formatDay(sub.nextRenewal!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Hero card: animated monthly total plus the subscription share bar.
class _Hero extends StatelessWidget {
  final String currency;
  final List<Subscription> subscriptions;
  final double monthlyTotal;
  final Map<String, double> otherCurrencies;

  const _Hero({
    required this.currency,
    required this.subscriptions,
    required this.monthlyTotal,
    required this.otherCurrencies,
  });

  @override
  Widget build(BuildContext context) {
    final caption = [
      '${subscriptions.length} subscriptions',
      '${formatMoney(monthlyTotal * 12, currency)}/yr',
      for (final entry in otherCurrencies.entries)
        '+ ${formatMoney(entry.value, entry.key)}/mo',
    ].join(' · ');

    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Text(
            'Recurring per month',
            style: TextStyle(
              fontSize: 15,
              color: Palette.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: monthlyTotal),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              formatMoney(value, currency),
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                color: Palette.label(context),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Palette.secondaryLabel(context),
            ),
          ),
          if (subscriptions.isNotEmpty && monthlyTotal > 0) ...[
            const SizedBox(height: 18),
            _ShareBar(subscriptions: subscriptions, total: monthlyTotal),
          ],
        ],
      ),
    );
  }
}

/// Monochrome share bar: top 4 subscriptions get accent-ramp shades, the
/// remainder is lumped into a neutral 'Other' segment.
class _ShareBar extends StatelessWidget {
  final List<Subscription> subscriptions;
  final double total;

  const _ShareBar({required this.subscriptions, required this.total});

  @override
  Widget build(BuildContext context) {
    final ramp = Palette.ramp(context);
    final top = subscriptions.take(4).toList();
    final otherAmount =
        subscriptions.skip(4).fold(0.0, (sum, s) => sum + s.monthlyAmount);

    int flexOf(double amount) =>
        (amount / total * 100).round().clamp(1, 100);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (var i = 0; i < top.length; i++)
                  Expanded(
                    flex: flexOf(top[i].monthlyAmount),
                    child: ColoredBox(color: ramp[i]),
                  ),
                if (otherAmount > 0)
                  Expanded(
                    flex: flexOf(otherAmount),
                    child: ColoredBox(color: Palette.track(context)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < top.length; i++)
              _LegendEntry(color: ramp[i], label: top[i].service),
            if (otherAmount > 0)
              _LegendEntry(color: Palette.track(context), label: 'Other'),
          ],
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendEntry({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style:
              TextStyle(fontSize: 12, color: Palette.secondaryLabel(context)),
        ),
      ],
    );
  }
}

/// "From x@gmail.com" when several inboxes are merged, else null (noise).
String? _attribution(BuildContext context, String sourceEmailId) {
  final email =
      context.read<AppController>().accountForInsight(sourceEmailId);
  return email == null ? null : 'From $email';
}


