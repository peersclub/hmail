import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/domain/backfill_stats.dart';
import 'package:hmail/domain/models.dart';

// Fixed clock — every date below is relative to this, never DateTime.now().
final now = DateTime(2030, 6, 15, 10);

Subscription sub({
  String service = 'Service',
  double amount = 100,
  String currency = 'INR',
  Cadence cadence = Cadence.monthly,
}) =>
    Subscription(
      service: service,
      amount: amount,
      currency: currency,
      cadence: cadence,
      lastSeen: now,
      sourceEmailId: 'e-sub',
    );

Bill bill({
  String issuer = 'Issuer',
  double amount = 500,
  String currency = 'INR',
  DateTime? dueDate,
}) =>
    Bill(
      issuer: issuer,
      amount: amount,
      currency: currency,
      dueDate: dueDate,
      lastSeen: now,
      sourceEmailId: 'e-bill',
    );

Delivery delivery({DeliveryStatus status = DeliveryStatus.shipped}) => Delivery(
      merchant: 'Amazon',
      status: status,
      lastSeen: now,
      sourceEmailId: 'e-del',
    );

EventItem event({DateTime? start, bool isCancelled = false}) => EventItem(
      title: 'Standup',
      start: start ?? now.add(const Duration(days: 1)),
      isCancelled: isCancelled,
      lastSeen: now,
      sourceEmailId: 'e-evt',
    );

BackfillStats stats(InsightSnapshot snapshot) =>
    BackfillStats.fromSnapshot(snapshot, now: now);

void main() {
  group('annual recurring', () {
    test('annualizes monthly x12 and keeps yearly as-is, per currency', () {
      final result = stats(InsightSnapshot(subscriptions: [
        sub(service: 'Netflix', amount: 100, cadence: Cadence.monthly),
        sub(service: 'Prime', amount: 599, cadence: Cadence.yearly),
        sub(service: 'GitHub', amount: 10, currency: 'USD'),
      ]));
      expect(result.annualRecurringByCurrency,
          {'INR': 100 * 12 + 599, 'USD': 10 * 12});
      expect(result.subscriptionCount, 3);
    });

    test('formats the dominant-currency total with grouping and /yr', () {
      final result = stats(InsightSnapshot(subscriptions: [
        sub(service: 'A', amount: 1200, cadence: Cadence.monthly),
        sub(service: 'B', amount: 4000, cadence: Cadence.yearly),
      ]));
      expect(result.dominantCurrency, 'INR');
      expect(result.annualRecurringDisplay, '₹18,400/yr');
    });

    test('picks USD when it carries the larger annual spend', () {
      final result = stats(InsightSnapshot(subscriptions: [
        sub(service: 'Small', amount: 100, currency: 'INR'),
        sub(service: 'Big', amount: 500, currency: 'USD'),
      ]));
      expect(result.dominantCurrency, 'USD');
      expect(result.annualRecurringDisplay, r'$6,000/yr');
    });
  });

  group('upcoming bills', () {
    test('counts dated bills and drops stale ones (overdue > 21 days)', () {
      final result = stats(InsightSnapshot(bills: [
        bill(amount: 300, dueDate: now.add(const Duration(days: 5))),
        bill(amount: 200, dueDate: now.subtract(const Duration(days: 10))),
        bill(amount: 999, dueDate: now.subtract(const Duration(days: 30))),
        bill(amount: 999, dueDate: null),
      ]));
      expect(result.upcomingBillsCount, 2);
      expect(result.upcomingBillsTotal, 500);
    });

    test('totals only the dominant currency', () {
      final result = stats(InsightSnapshot(bills: [
        bill(amount: 400, currency: 'INR',
            dueDate: now.add(const Duration(days: 3))),
        bill(amount: 50, currency: 'USD',
            dueDate: now.add(const Duration(days: 3))),
      ]));
      // No subscriptions — dominance falls back to the biggest bill pile.
      expect(result.dominantCurrency, 'INR');
      expect(result.upcomingBillsCount, 2);
      expect(result.upcomingBillsTotal, 400);
    });
  });

  test('counts only active deliveries', () {
    final result = stats(InsightSnapshot(deliveries: [
      delivery(status: DeliveryStatus.shipped),
      delivery(status: DeliveryStatus.outForDelivery),
      delivery(status: DeliveryStatus.delivered),
    ]));
    expect(result.activeDeliveryCount, 2);
  });

  test('counts upcoming meetings inside the 7-day window only', () {
    final result = stats(InsightSnapshot(events: [
      event(start: now.add(const Duration(days: 2))),
      event(start: now.add(const Duration(days: 6))),
      event(start: now.add(const Duration(days: 8))), // outside window
      event(start: now.subtract(const Duration(days: 1))), // past
      event(start: now.add(const Duration(days: 3)), isCancelled: true),
    ]));
    expect(result.meetingsThisWeekCount, 2);
  });

  group('headline', () {
    test('empty snapshot reads quiet', () {
      final result = stats(const InsightSnapshot());
      expect(result.headline, 'Your inbox looks quiet.');
      expect(result.annualRecurringDisplay, '₹0/yr');
      expect(result.subscriptionCount, 0);
      expect(result.upcomingBillsTotal, 0);
    });

    test('composes subscriptions, bills, and deliveries for a rich inbox', () {
      final result = stats(InsightSnapshot(
        subscriptions: [
          for (var i = 0; i < 8; i++)
            sub(service: 'Sub$i', amount: 150, cadence: Cadence.monthly),
          sub(service: 'Yearly', amount: 4000, cadence: Cadence.yearly),
        ],
        bills: [
          for (var i = 0; i < 3; i++)
            bill(issuer: 'Bill$i', dueDate: now.add(Duration(days: i + 1))),
        ],
        deliveries: [delivery(), delivery()],
      ));
      expect(
        result.headline,
        'Found 9 subscriptions costing ₹18,400/yr, 3 bills due, '
        'and 2 packages on the way.',
      );
    });

    test('degrades to a single fact with singular grammar', () {
      final result = stats(InsightSnapshot(deliveries: [delivery()]));
      expect(result.headline, 'Found 1 package on the way.');

      final two = stats(InsightSnapshot(
        subscriptions: [sub(amount: 100)],
        events: [event()],
      ));
      expect(two.headline,
          'Found 1 subscription costing ₹1,200/yr and 1 meeting this week.');
    });
  });
}
