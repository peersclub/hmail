/// Deterministic daily brief — no network, no keys.
///
/// The brief is a core feature, not an AI feature: this builder guarantees
/// every user gets one. When an AI gateway is configured its version replaces
/// this one; when it isn't (or the call fails), this is what renders.
library;

import 'models.dart';

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
  // Indian-style grouping is overkill here; plain grouping reads fine.
  final grouped = rounded.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$symbol$grouped';
}

/// "3pm" / "3:30pm"; empty for date-only (midnight) events.
String _clock(DateTime time) {
  if (time.hour == 0 && time.minute == 0) return '';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute =
      time.minute == 0 ? '' : ':${time.minute.toString().padLeft(2, '0')}';
  return '$hour$minute${time.hour < 12 ? 'am' : 'pm'}';
}

String _inDays(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final diff = that.difference(today).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}

DailyBrief buildRuleBrief(InsightSnapshot snapshot) {
  final now = DateTime.now();
  final soon = now.add(const Duration(days: 7));

  final overdue = snapshot.bills.where((b) => b.isOverdue).toList();
  final dueSoon = snapshot.bills
      .where((b) =>
          b.dueDate != null &&
          !b.isOverdue &&
          b.dueDate!.isBefore(soon))
      .toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  final renewing = snapshot.subscriptions
      .where((s) => s.nextRenewal != null && s.nextRenewal!.isAfter(now) && s.nextRenewal!.isBefore(soon))
      .toList()
    ..sort((a, b) => a.nextRenewal!.compareTo(b.nextRenewal!));
  final arriving = snapshot.activeDeliveries;
  final outForDelivery =
      arriving.where((d) => d.status == DeliveryStatus.outForDelivery).toList();

  final meetingsToday = snapshot.todayEvents;
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final meetingsTomorrow = snapshot.upcomingEvents
      .where((e) =>
          e.start.year == tomorrow.year &&
          e.start.month == tomorrow.month &&
          e.start.day == tomorrow.day)
      .toList();
  // Back-to-back: a meeting starts before (or right as) the previous one ends.
  var backToBack = false;
  for (var i = 0; i + 1 < meetingsToday.length; i++) {
    final end = meetingsToday[i].end ??
        meetingsToday[i].start.add(const Duration(minutes: 30));
    if (!meetingsToday[i + 1].start.isAfter(end)) backToBack = true;
  }

  // Headline: the two most urgent facts, joined.
  final fragments = <String>[];
  if (overdue.isNotEmpty) {
    fragments.add(
        '${overdue.first.issuer} (${_money(overdue.first.amount, overdue.first.currency)}) is overdue');
  }
  if (meetingsToday.isNotEmpty && fragments.length < 2) {
    final firstAt = _clock(meetingsToday.first.start);
    fragments.add(meetingsToday.length == 1
        ? '${meetingsToday.first.title}${firstAt.isEmpty ? '' : ' at $firstAt'} is on today'
        : '${meetingsToday.length} meetings today'
            '${backToBack ? ' (some back-to-back)' : firstAt.isEmpty ? '' : ', first at $firstAt'}');
  }
  if (dueSoon.isNotEmpty && fragments.length < 2) {
    final total = dueSoon.fold(0.0, (sum, b) => sum + b.amount);
    fragments.add(dueSoon.length == 1
        ? '${dueSoon.first.issuer} is due ${_inDays(dueSoon.first.dueDate!)}'
        : '${dueSoon.length} bills (${_money(total, dueSoon.first.currency)}) land this week');
  }
  if (outForDelivery.isNotEmpty && fragments.length < 2) {
    fragments.add(
        'your ${outForDelivery.first.merchant} order is out for delivery');
  } else if (arriving.isNotEmpty && fragments.length < 2) {
    fragments.add(
        '${arriving.length == 1 ? 'a package is' : '${arriving.length} packages are'} on the way');
  }
  if (renewing.isNotEmpty && fragments.length < 2) {
    fragments.add(
        '${renewing.first.service} renews ${_inDays(renewing.first.nextRenewal!)}');
  }

  final headline = fragments.isEmpty
      ? 'All quiet — nothing needs your attention right now.'
      : '${fragments.join(', and ')}.'.replaceFirst(
          fragments.first[0], fragments.first[0].toUpperCase());

  final bullets = <String>[
    for (final bill in overdue.take(2))
      '${bill.issuer} ${_money(bill.amount, bill.currency)} is past due — pay now.',
    for (final event in meetingsToday.take(2))
      '${event.title}${_clock(event.start).isEmpty ? ' today' : ' at ${_clock(event.start)}'}'
          '${event.meetingUrl != null ? ' — join link ready' : ''}.',
    for (final bill in dueSoon.take(2))
      '${bill.issuer} ${_money(bill.amount, bill.currency)} due ${_inDays(bill.dueDate!)}.',
    for (final event in meetingsTomorrow.take(1))
      '${event.title} tomorrow${_clock(event.start).isEmpty ? '' : ' at ${_clock(event.start)}'}.',
    for (final sub in renewing.take(2))
      '${sub.service} renews ${_inDays(sub.nextRenewal!)} (${_money(sub.amount, sub.currency)}).',
    for (final delivery in outForDelivery.take(1))
      '${delivery.merchant} package is out for delivery${delivery.carrier != null ? ' via ${delivery.carrier}' : ''}.',
    for (final item in snapshot.attention.take(1)) item.title,
  ].take(4).toList();

  return DailyBrief(
    headline: headline,
    bullets: bullets,
    generatedAt: DateTime.now(),
  );
}
