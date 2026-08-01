/// First-scan reveal numbers — the onboarding "money shot".
///
/// After the first deep scan the app shows "here's what was hiding in your
/// inbox". A monthly figure undersells it: annualising subscriptions turns
/// "₹1,530/mo" into "₹18,400/yr" — the number that actually lands. Pure Dart,
/// no clock inside the math: pass `now` and the same snapshot always yields
/// the same stats.
library;

import 'models.dart';

/// Duplicated from brief_builder's private `_money` — same output, worth the
/// few lines over exposing formatting internals across the domain layer.
String _money(double amount, String currency) {
  final symbol = switch (currency) {
    'INR' => '₹',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    _ => '$currency ',
  };
  final rounded =
      amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(2);
  final grouped = rounded.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$symbol$grouped';
}

/// Mirrors [Bill.isStale] but against an injected clock — bills more than
/// three weeks past due were almost certainly paid.
bool _isStale(Bill bill, DateTime anchor) {
  final due = bill.dueDate;
  if (due == null) return false;
  final days = DateTime(due.year, due.month, due.day)
      .difference(DateTime(anchor.year, anchor.month, anchor.day))
      .inDays;
  return days < -21;
}

String _plural(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');

/// What the deep scan found, shaped for the onboarding reveal screen.
class BackfillStats {
  /// Annualised subscription spend per currency: yearly plans count as-is,
  /// everything else as monthly × 12. Kept per-currency because mixing
  /// currencies into one number would be a lie.
  final Map<String, double> annualRecurringByCurrency;

  /// The currency carrying the largest annual recurring spend (bills break
  /// the tie when there are no subscriptions; INR when there's nothing).
  final String dominantCurrency;

  /// e.g. "₹18,400/yr" — the annual total in [dominantCurrency].
  final String annualRecurringDisplay;

  final int subscriptionCount;

  /// Sum of unpaid upcoming bills in [dominantCurrency] only.
  final double upcomingBillsTotal;

  /// All unpaid upcoming bills, any currency.
  final int upcomingBillsCount;

  final int activeDeliveryCount;

  /// Upcoming (non-cancelled) events starting within the next 7 days.
  final int meetingsThisWeekCount;

  /// One sentence composing the most impressive facts, e.g. "Found 9
  /// subscriptions costing ₹18,400/yr, 3 bills due, and 2 packages on the
  /// way." Empty sections drop out; a fully empty inbox reads
  /// "Your inbox looks quiet."
  final String headline;

  const BackfillStats._({
    required this.annualRecurringByCurrency,
    required this.dominantCurrency,
    required this.annualRecurringDisplay,
    required this.subscriptionCount,
    required this.upcomingBillsTotal,
    required this.upcomingBillsCount,
    required this.activeDeliveryCount,
    required this.meetingsThisWeekCount,
    required this.headline,
  });

  factory BackfillStats.fromSnapshot(InsightSnapshot snapshot, {DateTime? now}) {
    final anchor = now ?? DateTime.now();

    final annual = <String, double>{};
    for (final sub in snapshot.subscriptions) {
      final yearly =
          sub.cadence == Cadence.yearly ? sub.amount : sub.monthlyAmount * 12;
      annual[sub.currency] = (annual[sub.currency] ?? 0) + yearly;
    }

    final upcomingBills = snapshot.bills
        .where((b) => b.dueDate != null && !_isStale(b, anchor))
        .toList();
    final billTotals = <String, double>{};
    for (final bill in upcomingBills) {
      billTotals[bill.currency] = (billTotals[bill.currency] ?? 0) + bill.amount;
    }

    final dominantSource = annual.isNotEmpty ? annual : billTotals;
    final dominant = dominantSource.isEmpty
        ? 'INR'
        : dominantSource.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;

    final billsTotal = billTotals[dominant] ?? 0;
    final activeDeliveries = snapshot.deliveries.where((d) => d.isActive).length;
    final weekEnd = anchor.add(const Duration(days: 7));
    final meetings = snapshot.events
        .where((e) =>
            !e.isCancelled && e.start.isAfter(anchor) && !e.start.isAfter(weekEnd))
        .length;

    final display = '${_money(annual[dominant] ?? 0, dominant)}/yr';
    final subCount = snapshot.subscriptions.length;

    // Headline: only the sections that have something to show, joined into
    // one sentence — silence about empty sections beats a row of zeros.
    final fragments = <String>[
      if (subCount > 0)
        '$subCount ${_plural(subCount, 'subscription')} costing $display',
      if (upcomingBills.isNotEmpty)
        '${upcomingBills.length} ${_plural(upcomingBills.length, 'bill')} due',
      if (activeDeliveries > 0)
        '$activeDeliveries ${_plural(activeDeliveries, 'package')} on the way',
      if (meetings > 0) '$meetings ${_plural(meetings, 'meeting')} this week',
    ];
    final headline = switch (fragments.length) {
      0 => 'Your inbox looks quiet.',
      1 => 'Found ${fragments.first}.',
      2 => 'Found ${fragments.first} and ${fragments.last}.',
      _ =>
        'Found ${fragments.sublist(0, fragments.length - 1).join(', ')}, and ${fragments.last}.',
    };

    return BackfillStats._(
      annualRecurringByCurrency: Map.unmodifiable(annual),
      dominantCurrency: dominant,
      annualRecurringDisplay: display,
      subscriptionCount: subCount,
      upcomingBillsTotal: billsTotal,
      upcomingBillsCount: upcomingBills.length,
      activeDeliveryCount: activeDeliveries,
      meetingsThisWeekCount: meetings,
      headline: headline,
    );
  }
}
