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
  group('Indian bill senders', () {
    test('detects a Tata Power bill with due date', () {
      final bill = extractBill(email(
        from: 'noreply@tatapower.com',
        subject: 'Your Tata Power bill for July 2026',
        body: 'Amount due: ₹2,340. Due date: 18 Aug 2026. '
            'Pay before the due date to avoid late payment charges.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'Tata Power'); // not the generic 'Electricity'
      expect(bill.amount, 2340);
      expect(bill.dueDate, DateTime(2026, 8, 18));
    });

    test('detects an MSEDCL bill from the mahadiscom domain', () {
      final bill = extractBill(email(
        from: 'billing@mahadiscom.in',
        subject: 'MSEDCL: Electricity bill is due',
        body: 'Total amount due: ₹1,120 by 12 Aug 2026.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'MSEDCL');
      expect(bill.amount, 1120);
      expect(bill.dueDate, DateTime(2026, 8, 12));
    });

    test('labels HDFC Ergo premium as insurance, not HDFC Card', () {
      final bill = extractBill(email(
        from: 'care@hdfcergo.com',
        subject: 'Health insurance premium payment due',
        body: 'Premium amount due: ₹8,905 by 25 Aug 2026. '
            'Renew your policy on time to stay covered.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'HDFC Ergo');
      expect(bill.amount, 8905);
    });

    test('detects a Kotak credit card statement', () {
      final bill = extractBill(email(
        from: 'creditcards@kotak.com',
        subject: 'Kotak credit card statement — payment due',
        body: 'Total amount due: ₹23,410.50. Due by 19 Aug 2026.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'Kotak Card');
      expect(bill.amount, 23410.50);
    });

    test('detects a Tata Play recharge reminder', () {
      final bill = extractBill(email(
        from: 'noreply@tataplay.com',
        subject: 'Your Tata Play recharge is due',
        body: 'Recharge amount: ₹599. Due date: 10 Aug 2026.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'Tata Play');
      expect(bill.amount, 599);
      expect(bill.dueDate, DateTime(2026, 8, 10));
    });

    test('detects an LIC premium reminder', () {
      final bill = extractBill(email(
        from: 'noreply@licindia.com',
        subject: 'Premium due reminder for your LIC policy',
        body: 'Premium of ₹12,450 is due by 20 Aug 2026. Pay online.',
      ));
      expect(bill, isNotNull);
      expect(bill!.issuer, 'LIC');
      expect(bill.amount, 12450);
    });
  });

  group('Indian subscription senders', () {
    test('detects a SonyLIV renewal', () {
      final sub = extractSubscription(email(
        from: 'mailer@sonyliv.com',
        subject: 'Your SonyLIV Premium subscription is renewed',
        body: 'We charged ₹299 for your monthly plan. Renews on 1 Sep 2026.',
      ));
      expect(sub, isNotNull);
      expect(sub!.service, 'SonyLIV');
      expect(sub.amount, 299);
      expect(sub.cadence, Cadence.monthly);
      expect(sub.nextRenewal, DateTime(2026, 9, 1));
    });

    test('detects a Times Prime yearly membership', () {
      final sub = extractSubscription(email(
        from: 'hello@timesprime.com',
        subject: 'Times Prime membership renewal receipt',
        body: 'Annual membership: ₹1,199 per year.',
      ));
      expect(sub, isNotNull);
      expect(sub!.service, 'Times Prime');
      expect(sub.amount, 1199);
      expect(sub.cadence, Cadence.yearly);
    });

    test('detects Swiggy One via the subject, not the swiggy domain', () {
      final sub = extractSubscription(email(
        from: 'noreply@swiggy.in',
        subject: 'Your Swiggy One membership has been renewed',
        body: 'You paid ₹899. Benefits valid till 30 Jul 2027.',
      ));
      expect(sub, isNotNull);
      expect(sub!.service, 'Swiggy One');
      expect(sub.amount, 899);
    });
  });

  group('Indian delivery senders', () {
    test('detects a Zepto order out for delivery', () {
      final delivery = extractDelivery(email(
        from: 'no-reply@zeptonow.com',
        subject: 'Your order is on the way',
        body: 'Your Zepto order is out for delivery and will arrive in minutes.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Zepto');
      expect(delivery.status, DeliveryStatus.outForDelivery);
    });

    test('detects a delivered Meesho order', () {
      final delivery = extractDelivery(email(
        from: 'updates@meesho.com',
        subject: 'Delivered: your Meesho order',
        body: 'Your package was delivered today. Rate your experience.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Meesho');
      expect(delivery.status, DeliveryStatus.delivered);
      expect(delivery.isActive, isFalse);
    });

    test('detects an XpressBees shipment with tracking number', () {
      final delivery = extractDelivery(email(
        from: 'orders@snapdeal.com',
        subject: 'Your order has been shipped',
        body: 'Shipped via XpressBees. Tracking number: XB4501982236714.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Snapdeal');
      expect(delivery.status, DeliveryStatus.shipped);
      expect(delivery.carrier, 'XpressBees');
      expect(delivery.trackingNumber, 'XB4501982236714');
    });

    test('detects an Ecom Express shipment with an ETA', () {
      final delivery = extractDelivery(email(
        from: 'order@decathlon.in',
        subject: 'Your order is on its way',
        body: 'Dispatched via Ecom Express. Arriving 6 Aug 2026.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Decathlon');
      expect(delivery.status, DeliveryStatus.shipped);
      expect(delivery.carrier, 'Ecom Express');
      expect(delivery.eta, DateTime(2026, 8, 6));
    });

    test('detects a confirmed JioMart order', () {
      final delivery = extractDelivery(email(
        from: 'noreply@jiomart.com',
        subject: 'Order confirmed: arriving soon',
        body: 'Thanks for shopping with JioMart. Order total ₹1,240.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'JioMart');
      expect(delivery.status, DeliveryStatus.ordered);
    });
  });

  group('precision — no false positives', () {
    test('a newsletter about the power sector is not a bill', () {
      final message = email(
        from: 'newsletter@moneycontrol.com',
        subject: 'Power sector weekly: five stories to read',
        body: 'Tata Power rose 5% this week. Adani Electricity won a '
            'transmission bid worth ₹1,200 crore.',
      );
      expect(extractBill(message), isNull);
      expect(extractSubscription(message), isNull);
    });

    test('a merchant promo is not a delivery', () {
      final message = email(
        from: 'offers@meesho.com',
        subject: 'Mega Blowout Sale is live — up to 80% off',
        body: 'Prices start at ₹99. Shop bestsellers now.',
      );
      expect(extractDelivery(message), isNull);
    });
  });
}
