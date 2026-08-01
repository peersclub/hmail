import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/extractors/extractors.dart';
import 'package:hmail/domain/models.dart';

EmailMeta email({
  String id = 'test-1',
  String from = 'noreply@example.com',
  String subject = '',
  String snippet = '',
  String body = '',
  DateTime? date,
}) =>
    EmailMeta(
      id: id,
      from: from,
      subject: subject,
      snippet: snippet,
      body: body,
      date: date ?? DateTime(2026, 8, 1),
    );

void main() {
  group('extractMoney', () {
    test('parses rupee amounts with commas', () {
      final match = extractMoney('Total: ₹1,840.50 payable');
      expect(match, isNotNull);
      expect(match!.amount, 1840.50);
      expect(match.currency, 'INR');
    });

    test('parses dollar amounts', () {
      final match = extractMoney(r'You were charged $15.99 today');
      expect(match!.amount, 15.99);
      expect(match.currency, 'USD');
    });

    test('parses Rs. prefix', () {
      final match = extractMoney('Amount due Rs. 649');
      expect(match!.amount, 649);
      expect(match.currency, 'INR');
    });

    test('returns null when no money present', () {
      expect(extractMoney('See you at 5 o\'clock'), isNull);
    });
  });

  group('extractDate', () {
    final anchor = DateTime(2026, 8, 1);

    test('parses month-name dates', () {
      final date = extractDate('due on December 15', anchor: anchor);
      expect(date, DateTime(2026, 12, 15));
    });

    test('parses day-first month names', () {
      final date = extractDate('payable by 15 Dec 2026', anchor: anchor);
      expect(date, DateTime(2026, 12, 15));
    });

    test('rolls to next year when month already passed', () {
      final date = extractDate('renews on January 5', anchor: anchor);
      expect(date, DateTime(2027, 1, 5));
    });

    test('parses numeric day-first dates', () {
      final date = extractDate('due 15/08/2026', anchor: anchor);
      expect(date, DateTime(2026, 8, 15));
    });
  });

  group('extractSubscription', () {
    test('detects a Netflix renewal', () {
      final sub = extractSubscription(email(
        from: 'info@mailer.netflix.com',
        subject: 'Your Netflix subscription renewal',
        body: 'Your plan renews on September 1 for ₹649/month.',
      ));
      expect(sub, isNotNull);
      expect(sub!.service, 'Netflix');
      expect(sub.amount, 649);
      expect(sub.cadence, Cadence.monthly);
      expect(sub.nextRenewal, DateTime(2026, 9, 1));
    });

    test('detects yearly cadence', () {
      final sub = extractSubscription(email(
        from: 'no-reply@apple.com',
        subject: 'Receipt for your iCloud+ subscription',
        body: 'Annual plan: ₹999 per year.',
      ));
      expect(sub!.cadence, Cadence.yearly);
      expect(sub.monthlyAmount, closeTo(999 / 12, 0.01));
    });

    test('ignores unrelated mail', () {
      expect(
        extractSubscription(email(subject: 'Lunch tomorrow?', body: 'Pizza?')),
        isNull,
      );
    });
  });

  group('extractBill', () {
    test('detects an electricity bill with due date', () {
      final bill = extractBill(email(
        from: 'billing@bescom.co.in',
        subject: 'Electricity bill for July',
        body: 'Amount due: ₹1,840. Payment due by August 15, 2026.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'BESCOM');
      expect(bill.amount, 1840);
      expect(bill.dueDate, DateTime(2026, 8, 15));
      expect(bill.isOverdue, isFalse);
    });

    test('picks the amount near due-language, not a decoy offer', () {
      // Regression: real SBI email led with "₹4 reward points" before the bill.
      final bill = extractBill(email(
        from: 'statements@sbicard.com',
        subject: 'Your SBI Card statement',
        body:
            'You earned ₹4 in rewards this cycle. Total amount due: ₹19,340.52 by 8 Aug 2026.',
      ));
      expect(bill!.amount, 19340.52);
    });

    test('a bill due today is not overdue', () {
      final now = DateTime.now();
      final bill = Bill(
        issuer: 'Cred',
        amount: 100,
        currency: 'INR',
        dueDate: DateTime(now.year, now.month, now.day),
        lastSeen: now,
        sourceEmailId: 'x',
      );
      expect(bill.isOverdue, isFalse);
      expect(bill.dueWithin(const Duration(days: 10)), isTrue);
    });

    test('bills weeks past due are stale', () {
      final bill = Bill(
        issuer: 'SBI Card',
        amount: 100,
        currency: 'INR',
        dueDate: DateTime.now().subtract(const Duration(days: 60)),
        lastSeen: DateTime.now(),
        sourceEmailId: 'x',
      );
      expect(bill.isStale, isTrue);
    });

    test('requires due-language to avoid claiming receipts', () {
      expect(
        extractBill(email(
          subject: 'Payment receipt',
          body: 'Thanks for your payment of ₹500.',
        )),
        isNull,
      );
    });
  });

  group('extractDelivery', () {
    test('detects an Amazon shipment with tracking', () {
      final delivery = extractDelivery(email(
        from: 'shipment-tracking@amazon.in',
        subject: 'Your package has shipped',
        body:
            'Arriving Saturday, August 8. Tracking number: BD4459812031 via Blue Dart.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Amazon');
      expect(delivery.status, DeliveryStatus.shipped);
      expect(delivery.carrier, 'Blue Dart');
      expect(delivery.trackingNumber, 'BD4459812031');
    });

    test('detects out for delivery', () {
      final delivery = extractDelivery(email(
        from: 'noreply@flipkart.com',
        subject: 'Update on your order',
        body: 'Your item is out for delivery today.',
      ));
      expect(delivery!.status, DeliveryStatus.outForDelivery);
      expect(delivery.merchant, 'Flipkart');
    });

    test('detects delivered', () {
      final delivery = extractDelivery(email(
        from: 'orders@myntra.com',
        subject: 'Delivered: your order',
        body: 'Your package was delivered.',
      ));
      expect(delivery!.status, DeliveryStatus.delivered);
      expect(delivery.isActive, isFalse);
    });
  });

  group('delivery honesty', () {
    test('a product email saying "we shipped" is not a delivery', () {
      expect(
        extractDelivery(email(
          from: 'GitHub <noreply@github.com>',
          subject: 'We just shipped dark mode improvements',
          body: 'This week we shipped several features you asked for.',
        )),
        isNull,
      );
    });

    test('a real shipment with order language still extracts', () {
      final delivery = extractDelivery(email(
        from: 'orders@decathlon.in',
        subject: 'Shipped: your order',
        body: 'Your order is on the way. Tracking available.',
      ));
      expect(delivery, isNotNull);
    });

    test('deliveries with a long-past ETA are stale, not active', () {
      final delivery = Delivery(
        merchant: 'Decathlon',
        status: DeliveryStatus.shipped,
        eta: DateTime.now().subtract(const Duration(days: 3)),
        lastSeen: DateTime.now().subtract(const Duration(days: 4)),
        sourceEmailId: 'x',
      );
      expect(delivery.isStale, isTrue);
      expect(delivery.isActive, isFalse);
    });
  });

  group('runExtractors', () {
    test('routes each email to exactly one bucket', () {
      final result = runExtractors([
        email(
          id: 'a',
          from: 'info@netflix.com',
          subject: 'Subscription renewal receipt',
          body: 'Charged ₹649 monthly.',
        ),
        email(
          id: 'b',
          from: 'billing@airtel.in',
          subject: 'Your bill is ready',
          body: 'Amount due ₹599 by 20 Aug 2026.',
        ),
        email(
          id: 'c',
          from: 'ship@amazon.in',
          subject: 'Shipped: your order',
          body: 'On the way.',
        ),
        email(id: 'd', subject: 'Team standup notes', body: 'We discussed...'),
      ]);

      expect(result.subscriptions, hasLength(1));
      expect(result.bills, hasLength(1));
      expect(result.deliveries, hasLength(1));
      expect(result.unclaimed.map((e) => e.id), ['d']);
    });
  });
}