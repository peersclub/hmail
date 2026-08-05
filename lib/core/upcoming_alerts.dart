/// Proactive "upcoming" alerts — value without opening the app.
///
/// [buildUpcomingAlerts] is a pure function from an [InsightSnapshot] and a
/// fixed `now` to the short list of pushes worth scheduling ahead of time:
/// a subscription about to renew ("Netflix renews Thursday"), a bill landing
/// tomorrow ("BESCOM due tomorrow · ₹1,840"), a return window about to close
/// ("Myntra return window closes tomorrow").
///
/// Deliberately plugin-free and clock-free: it never touches
/// `DateTime.now()` (the model helpers that do — `isOverdue`, `isStale`,
/// `openReturns` — are re-derived here from the passed `now`), so the whole
/// thing is unit-testable with a frozen clock. Timezone conversion and the
/// "fire time already passed → bump to now+5min" rule belong to the
/// scheduling side (`NotificationService.syncUpcomingAlerts`); the builder
/// only emits the *target* local wall-clock instant.
///
/// Payload contract (decoded by the UI layer, same as every notification):
///  * insight has a link → `'action:<id>|<url>'` so a tap deep-links;
///  * no link → `'today'`, the Today-tab payload.
library;

import '../domain/models.dart';

/// Notification ids for upcoming alerts live in this closed namespace so the
/// scheduler can cancel exactly its own past output (and nothing else — the
/// daily brief and shown insights use ids outside it).
const upcomingAlertIdFloor = 50000;
const upcomingAlertIdCeiling = 59999;

/// One scheduled push. [fireAt] is a local wall-clock target; the service
/// converts it to the device timezone and bumps past instants forward.
class UpcomingAlert {
  /// Stable id in [upcomingAlertIdFloor]..[upcomingAlertIdCeiling], derived
  /// from the insight's identity + date so re-syncing the same state
  /// replaces rather than stacks.
  final int id;

  final String title;
  final String body;
  final DateTime fireAt;

  /// Opaque routing payload — `'action:<id>|<url>'` or `'today'`.
  final String payload;

  const UpcomingAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.payload,
  });

  @override
  String toString() => 'UpcomingAlert(#$id $fireAt "$title")';
}

/// Builds the alerts worth scheduling as of [now]:
///
///  * subscription renewal inside `(now, now+2d]` — fires at 09:00 two days
///    before the renewal;
///  * bill due inside `(now, now+1d]` (never overdue ones) — fires at 09:00
///    the day before it's due;
///  * return window (not warranty) closing inside `(now, now+1d]` — fires at
///    09:00 the day before the deadline.
///
/// Output is deterministic: same snapshot + same [now] → same alerts, same
/// ids, same order (soonest fire first).
List<UpcomingAlert> buildUpcomingAlerts(InsightSnapshot snapshot, DateTime now) {
  final alerts = <UpcomingAlert>[];
  final seen = <String>{};

  void add({
    required String key,
    required String title,
    required String body,
    required DateTime fireAt,
    String? url,
    String actionId = 'manage',
  }) {
    if (!seen.add(key)) return; // one alert per insight identity
    alerts.add(UpcomingAlert(
      id: upcomingAlertId(key),
      title: title,
      body: body,
      fireAt: fireAt,
      payload: url == null ? 'today' : 'action:$actionId|$url',
    ));
  }

  // Subscriptions renewing within two days.
  final renewalHorizon = now.add(const Duration(days: 2));
  for (final sub in snapshot.subscriptions) {
    final renewal = sub.nextRenewal;
    if (renewal == null) continue;
    if (!renewal.isAfter(now) || renewal.isAfter(renewalHorizon)) continue;
    final per = switch (sub.cadence) {
      Cadence.monthly => '/mo',
      Cadence.yearly => '/yr',
      Cadence.unknown => '',
    };
    add(
      key: 'renewal|${sub.service.toLowerCase()}|${_dayKey(renewal)}',
      title: '${sub.service} renews ${_dayLabel(now, renewal)}',
      body: '${_money(sub.amount, sub.currency)}$per — cancel or let it run.',
      fireAt: _nineAm(renewal, daysBefore: 2),
      url: sub.manageUrl,
    );
  }

  // Bills landing within a day. Window starts *after* now, so anything
  // already due (or overdue) never alerts — that's the daily brief's job.
  final billHorizon = now.add(const Duration(days: 1));
  for (final bill in snapshot.bills) {
    final due = bill.dueDate;
    if (due == null) continue;
    if (!due.isAfter(now) || due.isAfter(billHorizon)) continue;
    add(
      key: 'bill|${bill.issuer.toLowerCase()}|${_dayKey(due)}',
      title: '${bill.issuer} due ${_dayLabel(now, due)} · '
          '${_money(bill.amount, bill.currency)}',
      body: 'Pay it before it slips.',
      fireAt: _nineAm(due, daysBefore: 1),
      url: bill.payUrl,
      actionId: 'pay',
    );
  }

  // Return windows (money you can still get back) closing within a day.
  // Warranties expire on the same model but aren't a same-day errand.
  for (final item in snapshot.returns) {
    if (item.kind != ReturnKind.returnWindow) continue;
    if (!item.deadline.isAfter(now) || item.deadline.isAfter(billHorizon)) {
      continue;
    }
    add(
      key: 'return|${item.merchant.toLowerCase()}|${_dayKey(item.deadline)}',
      title:
          '${item.merchant} return window closes ${_dayLabel(now, item.deadline)}',
      body: item.item == null
          ? 'Last day to send it back.'
          : '${item.item} — send it back or keep it.',
      fireAt: _nineAm(item.deadline, daysBefore: 1),
      url: item.url,
    );
  }

  alerts.sort((a, b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return alerts;
}

/// Maps a dedupe key (e.g. `'renewal|netflix|2026-08-06'`) into the alert id
/// namespace. FNV-1a rather than `String.hashCode` because the id must be
/// identical across runs and platforms — it's what makes re-scheduling
/// replace instead of stack.
int upcomingAlertId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  const span = upcomingAlertIdCeiling - upcomingAlertIdFloor + 1;
  return upcomingAlertIdFloor + hash % span;
}

/// 09:00 local, [daysBefore] calendar days ahead of [event]'s day. May be in
/// the past relative to the build's `now` — the scheduler bumps those.
DateTime _nineAm(DateTime event, {required int daysBefore}) =>
    DateTime(event.year, event.month, event.day - daysBefore, 9);

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "today" / "tomorrow" / weekday name, by calendar day relative to [now].
String _dayLabel(DateTime now, DateTime date) {
  final diff = DateTime(date.year, date.month, date.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return _weekdays[date.weekday - 1];
}

/// Same symbol/grouping rules as the brief builder — one visual language for
/// money everywhere the user reads it.
String _money(double amount, String currency) {
  final symbol = switch (currency) {
    'INR' => '₹',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    _ => '$currency ',
  };
  final rounded = amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2);
  final grouped = rounded.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$symbol$grouped';
}
