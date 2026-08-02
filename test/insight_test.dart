import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/domain/insight.dart';
import 'package:hmail/domain/insight_mapper.dart';
import 'package:hmail/domain/models.dart';

Insight _mk({
  required InsightDomain domain,
  DateTime? anchor,
  bool overdue = false,
  int weight = 50,
  String id = 'x',
}) =>
    Insight(
      id: id,
      domain: domain,
      title: id,
      icon: domain.icon,
      anchorDate: anchor,
      overdue: overdue,
      weight: weight,
    );

void main() {
  final now = DateTime.now();

  group('urgency tiers', () {
    test('overdue is always imminent', () {
      expect(_mk(domain: InsightDomain.money, overdue: true).urgency,
          UrgencyTier.imminent);
    });
    test('within 6 hours is imminent', () {
      expect(
          _mk(domain: InsightDomain.work, anchor: now.add(const Duration(hours: 3)))
              .urgency,
          UrgencyTier.imminent);
    });
    test('within 3 days is near', () {
      expect(
          _mk(domain: InsightDomain.money, anchor: now.add(const Duration(days: 2)))
              .urgency,
          UrgencyTier.near);
    });
    test('far future and null are ambient', () {
      expect(
          _mk(domain: InsightDomain.money, anchor: now.add(const Duration(days: 30)))
              .urgency,
          UrgencyTier.ambient);
      expect(_mk(domain: InsightDomain.content).urgency, UrgencyTier.ambient);
    });
  });

  group('rankInsights', () {
    test('imminent outranks near outranks ambient regardless of weight', () {
      final ambientHeavy =
          _mk(domain: InsightDomain.security, weight: 100, id: 'ambient');
      final nearLight = _mk(
          domain: InsightDomain.content,
          weight: 10,
          anchor: now.add(const Duration(days: 1)),
          id: 'near');
      final ranked = rankInsights([ambientHeavy, nearLight]);
      expect(ranked.first.id, 'near',
          reason: 'a near-deadline item beats a heavier ambient one');
    });

    test('within a tier, higher weight wins (security over a same-day bill)', () {
      final otp = _mk(
          domain: InsightDomain.security,
          weight: 100,
          anchor: now.add(const Duration(hours: 1)),
          id: 'otp');
      final billToday = _mk(
          domain: InsightDomain.money,
          weight: 70,
          anchor: now.add(const Duration(hours: 2)),
          id: 'bill');
      final ranked = rankInsights([billToday, otp]);
      expect(ranked.first.id, 'otp');
    });
  });

  group('snapshotToInsights', () {
    test('maps every domain and weights overdue bills above renewals', () {
      final snap = InsightSnapshot(
        bills: [
          Bill(
            issuer: 'BESCOM',
            amount: 1840,
            currency: 'INR',
            dueDate: now.subtract(const Duration(days: 1)),
            lastSeen: now,
            sourceEmailId: 'b1',
          ),
        ],
        subscriptions: [
          Subscription(
            service: 'Netflix',
            amount: 649,
            currency: 'INR',
            cadence: Cadence.monthly,
            nextRenewal: now.add(const Duration(days: 5)),
            lastSeen: now,
            sourceEmailId: 's1',
          ),
        ],
        feed: [
          FeedItem(
            kind: FeedKind.article,
            source: 'The Ken',
            title: 'A story',
            date: now,
            lastSeen: now,
            sourceEmailId: 'f1',
          ),
        ],
      );
      final insights = snapshotToInsights(snap);
      expect(insights.map((i) => i.domain),
          containsAll([InsightDomain.money, InsightDomain.content]));
      final bill = insights.firstWhere((i) => i.id.startsWith('bill:'));
      final sub = insights.firstWhere((i) => i.id.startsWith('sub:'));
      expect(bill.weight, greaterThan(sub.weight));
      expect(bill.overdue, isTrue);
    });

    test('presentDomains lists only domains that have data, in enum order', () {
      final snap = InsightSnapshot(feed: [
        FeedItem(
          kind: FeedKind.video,
          source: 'YouTube',
          title: 'v',
          date: now,
          lastSeen: now,
          sourceEmailId: 'f',
        ),
      ]);
      final domains = presentDomains(snapshotToInsights(snap));
      expect(domains, [InsightDomain.content]);
    });
  });
}
