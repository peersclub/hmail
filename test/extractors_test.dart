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

  feedTests();
  travelTests();
  paymentTests();

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
void feedTests() {
  group('extractFeed', () {
    EmailMeta e({String from = '', String subject = '', String body = ''}) =>
        EmailMeta(
            id: 'f',
            from: from,
            subject: subject,
            snippet: '',
            body: body,
            date: DateTime(2026, 8, 1));

    test('The Ken article becomes an article feed item', () {
      final item = extractFeed(e(
        from: 'The Ken <newsletters@theken.com>',
        subject: 'The quick-commerce shakeout',
      ));
      expect(item, isNotNull);
      expect(item!.kind, FeedKind.article);
      expect(item.source, 'The Ken');
    });

    test('YouTube upload becomes a video and strips the "uploaded:" prefix', () {
      final item = extractFeed(e(
        from: 'YouTube <noreply@youtube.com>',
        subject: 'Veritasium uploaded: The riddle',
      ));
      expect(item!.kind, FeedKind.video);
      expect(item.title, 'The riddle');
    });

    test('Substack post is content, but a Substack receipt stays money', () {
      final post = extractFeed(e(
        from: 'Lenny <lenny@substack.com>',
        subject: 'New post: discovery',
      ));
      expect(post, isNotNull);
      // A receipt routes to subscription, not feed, via runExtractors ordering.
      final routed = runExtractors([
        e(
          from: 'Substack <receipts@substack.com>',
          subject: 'Your subscription receipt',
          body: 'Payment successful: \$8/month subscription.',
        ),
      ]);
      expect(routed.subscriptions, isNotEmpty);
      expect(routed.feed, isEmpty);
    });

    test('GitHub "we shipped" notification is never a read', () {
      expect(
        extractFeed(e(
          from: 'GitHub <noreply@github.com>',
          subject: 'New release published',
        )),
        isNull,
      );
    });
  });
}

void travelTests() {
  EmailMeta e({String from = '', String subject = '', String body = ''}) =>
      EmailMeta(
          id: 't',
          from: from,
          subject: subject,
          snippet: '',
          body: body,
          date: DateTime(2026, 8, 1));

  group('extractTravel', () {
    test('an IndiGo e-ticket becomes a flight with route and PNR', () {
      final t = extractTravel(e(
        from: 'IndiGo <noreply@goindigo.in>',
        subject: 'Your e-ticket, PNR X4K9Q2',
        body: 'Booking confirmed. PNR: X4K9Q2. Departure BLR → DEL.',
      ));
      expect(t, isNotNull);
      expect(t!.kind, TravelKind.flight);
      expect(t.provider, 'IndiGo');
      expect(t.route, 'BLR → DEL');
      expect(t.code, 'X4K9Q2');
    });

    test('a fare-marketing blast from an airline is not a trip', () {
      expect(
        extractTravel(e(
          from: 'IndiGo <offers@goindigo.in>',
          subject: 'Lowest fares of the season — flat 20% off, book now and save',
          body: 'Grab the deal before the sale is live ends.',
        )),
        isNull,
      );
    });

    test('unknown sender needs strong travel language', () {
      expect(
        extractTravel(e(
          from: 'random@example.com',
          subject: 'A flight of fancy',
          body: 'Just musing about travel.',
        )),
        isNull,
      );
      final t = extractTravel(e(
        from: 'bookings@somewhere.com',
        subject: 'Booking confirmed',
        body: 'Your itinerary is attached. PNR ABC123.',
      ));
      expect(t, isNotNull);
    });

    test('runExtractors routes a booking to travel, not delivery', () {
      final r = runExtractors([
        e(
          from: 'MakeMyTrip <trips@makemytrip.com>',
          subject: 'Booking confirmed: your hotel reservation',
          body: 'Reservation confirmed. Check-in 10 Aug 2026.',
        ),
      ]);
      expect(r.travel, isNotEmpty);
      expect(r.deliveries, isEmpty);
    });
  });
}

void paymentTests() {
  EmailMeta e({String from = '', String subject = '', String body = ''}) =>
      EmailMeta(
          id: 'p',
          from: from,
          subject: subject,
          snippet: '',
          body: body,
          date: DateTime(2026, 8, 1));

  group('extractPayment', () {
    test('a declined payment is a failed alert with the amount', () {
      final a = extractPayment(e(
        from: 'Netflix <info@netflix.com>',
        subject: 'Your payment was declined',
        body: 'Payment failed: could not process your ₹649 payment.',
      ));
      expect(a, isNotNull);
      expect(a!.kind, PaymentKind.failed);
      expect(a.amount, 649);
    });

    test('a processed refund is a refund alert', () {
      final a = extractPayment(e(
        from: 'Amazon <auto@amazon.in>',
        subject: 'Refund processed',
        body: 'Refund of ₹1,299 has been refunded to your card.',
      ));
      expect(a!.kind, PaymentKind.refund);
      expect(a.amount, 1299);
    });

    test('an ordinary receipt is not a payment alert', () {
      expect(
        extractPayment(e(
          from: 'x@y.com', subject: 'Receipt', body: 'Payment successful ₹5.')),
        isNull,
      );
    });

    test('runExtractors routes a failed payment to payments, not bills', () {
      final r = runExtractors([
        e(
          from: 'HDFC <alerts@hdfcbank.net>',
          subject: 'Autopay failed',
          body: 'Your autopay failed for ₹1,840 due to insufficient balance.',
        ),
      ]);
      expect(r.payments, isNotEmpty);
      expect(r.payments.first.kind, PaymentKind.failed);
    });
  });

  group('extractReturn', () {
    test('an open return window with a deadline is a return item', () {
      final r = extractReturn(email(
        from: 'Myntra <orders@myntra.com>',
        subject: 'Your order was delivered',
        body: 'Delivered. Eligible for return by 15 Aug 2026. Start a return.',
      ));
      expect(r, isNotNull);
      expect(r!.kind, ReturnKind.returnWindow);
      expect(r.merchant, 'Myntra');
      expect(r.deadline, DateTime(2026, 8, 15));
    });

    test('a warranty with an expiry date is a warranty item', () {
      final r = extractReturn(email(
        from: 'boAt <care@boat-lifestyle.com>',
        subject: 'Your product warranty',
        body: 'Warranty valid until 20 Dec 2026.',
      ));
      expect(r, isNotNull);
      expect(r!.kind, ReturnKind.warranty);
      expect(r.deadline, DateTime(2026, 12, 20));
    });

    test('return language with no parseable date is ignored (footer noise)', () {
      expect(
        extractReturn(email(
          from: 'shop@example.com',
          subject: 'Thanks for your order',
          body: 'Easy returns on all items. See our return policy for details.',
        )),
        isNull,
        reason: 'a bare "returns" phrase with no deadline is not actionable',
      );
    });

    test('runExtractors routes a "delivered, return by X" to returns, '
        'not deliveries', () {
      final r = runExtractors([
        email(
          from: 'Myntra <orders@myntra.com>',
          subject: 'Your order was delivered',
          body: 'Delivered. Eligible for return by 15 Aug 2026.',
        ),
      ]);
      expect(r.returns, isNotEmpty, reason: 'returns win over the delivery rule');
      expect(r.deliveries, isEmpty);
    });
  });
}
