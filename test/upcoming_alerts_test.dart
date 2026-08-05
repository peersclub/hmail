import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/core/upcoming_alerts.dart';
import 'package:hmail/domain/models.dart';

// Frozen clock: Tuesday 4 Aug 2026, 10:00 local.
final now = DateTime(2026, 8, 4, 10);

Subscription _sub({
  String service = 'Netflix',
  double amount = 649,
  Cadence cadence = Cadence.monthly,
  DateTime? nextRenewal,
  String? manageUrl,
}) =>
    Subscription(
      service: service,
      amount: amount,
      currency: 'INR',
      cadence: cadence,
      nextRenewal: nextRenewal,
      lastSeen: now,
      sourceEmailId: 'e1',
      manageUrl: manageUrl,
    );

Bill _bill({
  String issuer = 'BESCOM',
  double amount = 1840,
  DateTime? dueDate,
  String? payUrl,
}) =>
    Bill(
      issuer: issuer,
      amount: amount,
      currency: 'INR',
      dueDate: dueDate,
      lastSeen: now,
      sourceEmailId: 'e2',
      payUrl: payUrl,
    );

ReturnItem _return({
  ReturnKind kind = ReturnKind.returnWindow,
  String merchant = 'Myntra',
  String? item,
  required DateTime deadline,
  String? url,
}) =>
    ReturnItem(
      kind: kind,
      merchant: merchant,
      item: item,
      deadline: deadline,
      lastSeen: now,
      sourceEmailId: 'e3',
      url: url,
    );

void main() {
  group('subscription renewals', () {
    test('renewal exactly two days out fires two days before at 9am', () {
      final snapshot = InsightSnapshot(
        subscriptions: [
          _sub(
            nextRenewal: DateTime(2026, 8, 6, 10),
            manageUrl: 'https://netflix.com/account',
          ),
        ],
      );
      final alerts = buildUpcomingAlerts(snapshot, now);

      expect(alerts, hasLength(1));
      final alert = alerts.single;
      // 6 Aug 2026 is a Thursday — the canonical copy.
      expect(alert.title, 'Netflix renews Thursday');
      expect(alert.body, '₹649/mo — cancel or let it run.');
      // Target instant, even though 9am today already passed at now=10:00;
      // bumping past instants forward is the scheduler's job.
      expect(alert.fireAt, DateTime(2026, 8, 4, 9));
      expect(alert.payload, 'action:manage|https://netflix.com/account');
    });

    test('renewal three days out is not alerted yet', () {
      final snapshot = InsightSnapshot(
        subscriptions: [_sub(nextRenewal: DateTime(2026, 8, 7, 12))],
      );
      expect(buildUpcomingAlerts(snapshot, now), isEmpty);
    });

    test('renewal at or before now is not alerted (window is exclusive)', () {
      final snapshot = InsightSnapshot(
        subscriptions: [
          _sub(service: 'Spotify', nextRenewal: now),
          _sub(service: 'Prime', nextRenewal: DateTime(2026, 8, 3)),
        ],
      );
      expect(buildUpcomingAlerts(snapshot, now), isEmpty);
    });

    test('renewal tomorrow says tomorrow; no manage link falls back to today',
        () {
      final snapshot = InsightSnapshot(
        subscriptions: [
          _sub(cadence: Cadence.yearly, nextRenewal: DateTime(2026, 8, 5, 9)),
        ],
      );
      final alert = buildUpcomingAlerts(snapshot, now).single;
      expect(alert.title, 'Netflix renews tomorrow');
      expect(alert.body, '₹649/yr — cancel or let it run.');
      expect(alert.payload, 'today');
    });
  });

  group('bills', () {
    test('bill due tomorrow alerts with amount', () {
      final snapshot = InsightSnapshot(
        bills: [
          _bill(
            dueDate: DateTime(2026, 8, 5),
            payUrl: 'https://bescom.example/pay',
          ),
        ],
      );
      final alert = buildUpcomingAlerts(snapshot, now).single;
      expect(alert.title, 'BESCOM due tomorrow · ₹1,840');
      expect(alert.fireAt, DateTime(2026, 8, 4, 9));
      expect(alert.payload, 'action:pay|https://bescom.example/pay');
    });

    test('overdue bill never alerts', () {
      final snapshot = InsightSnapshot(
        bills: [_bill(dueDate: DateTime(2026, 8, 3))],
      );
      expect(buildUpcomingAlerts(snapshot, now), isEmpty);
    });

    test('bill due beyond a day is not alerted yet', () {
      final snapshot = InsightSnapshot(
        bills: [_bill(dueDate: DateTime(2026, 8, 6))],
      );
      expect(buildUpcomingAlerts(snapshot, now), isEmpty);
    });
  });

  group('return windows', () {
    test('return window closing tomorrow alerts', () {
      final snapshot = InsightSnapshot(
        returns: [
          _return(deadline: DateTime(2026, 8, 5), item: 'Nike Pegasus'),
        ],
      );
      final alert = buildUpcomingAlerts(snapshot, now).single;
      expect(alert.title, 'Myntra return window closes tomorrow');
      expect(alert.body, 'Nike Pegasus — send it back or keep it.');
      expect(alert.payload, 'today');
    });

    test('warranty deadlines are ignored', () {
      final snapshot = InsightSnapshot(
        returns: [
          _return(kind: ReturnKind.warranty, deadline: DateTime(2026, 8, 5)),
        ],
      );
      expect(buildUpcomingAlerts(snapshot, now), isEmpty);
    });
  });

  group('ids', () {
    test('ids live in the 50000..59999 namespace', () {
      final snapshot = InsightSnapshot(
        subscriptions: [_sub(nextRenewal: DateTime(2026, 8, 6))],
        bills: [_bill(dueDate: DateTime(2026, 8, 5))],
        returns: [_return(deadline: DateTime(2026, 8, 5))],
      );
      final alerts = buildUpcomingAlerts(snapshot, now);
      expect(alerts, hasLength(3));
      for (final alert in alerts) {
        expect(alert.id, inInclusiveRange(50000, 59999));
      }
    });

    test('same insight builds to the same id every time', () {
      final snapshot = InsightSnapshot(
        subscriptions: [_sub(nextRenewal: DateTime(2026, 8, 6, 10))],
      );
      final first = buildUpcomingAlerts(snapshot, now).single;
      final second = buildUpcomingAlerts(snapshot, now).single;
      expect(second.id, first.id);
    });

    test('same insight on a different day gets a different id', () {
      final onThursday = buildUpcomingAlerts(
        InsightSnapshot(
          subscriptions: [_sub(nextRenewal: DateTime(2026, 8, 6, 10))],
        ),
        now,
      ).single;
      final onFriday = buildUpcomingAlerts(
        InsightSnapshot(
          subscriptions: [_sub(nextRenewal: DateTime(2026, 8, 7, 10))],
        ),
        DateTime(2026, 8, 5, 10),
      ).single;
      expect(onFriday.id, isNot(onThursday.id));
    });

    test('duplicate insight identities collapse to one alert', () {
      final snapshot = InsightSnapshot(
        subscriptions: [
          _sub(nextRenewal: DateTime(2026, 8, 6, 9)),
          _sub(nextRenewal: DateTime(2026, 8, 6, 21)),
        ],
      );
      expect(buildUpcomingAlerts(snapshot, now), hasLength(1));
    });
  });

  test('alerts come back sorted by fire time', () {
    final snapshot = InsightSnapshot(
      subscriptions: [
        _sub(nextRenewal: DateTime(2026, 8, 6, 10)), // fires 4 Aug 9am
      ],
      bills: [
        _bill(dueDate: DateTime(2026, 8, 5, 8)), // fires 4 Aug 9am
      ],
      returns: [
        _return(deadline: DateTime(2026, 8, 5, 8)), // fires 4 Aug 9am
      ],
    );
    final alerts = buildUpcomingAlerts(snapshot, now);
    expect(alerts, hasLength(3));
    for (var i = 0; i + 1 < alerts.length; i++) {
      expect(alerts[i].fireAt.isAfter(alerts[i + 1].fireAt), isFalse);
    }
  });
}
