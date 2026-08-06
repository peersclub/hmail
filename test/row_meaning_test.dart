/// Rows have to say what they are.
///
/// A bill row used to render a name, an amount and a date with no description at
/// all, which is unreadable the moment the name is an intermediary: "CRED · ₹599
/// · Due Tuesday" names the postman instead of the letter, because CRED is never
/// the biller — it forwards reminders for other billers. Razorpay, Billdesk and
/// the rest are the same shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/extractors/extractors.dart';
import 'package:hmail/domain/insight_mapper.dart';
import 'package:hmail/domain/models.dart';

EmailMeta _mail({
  required String from,
  required String subject,
  String body = '',
}) =>
    EmailMeta(
      id: 'e1',
      from: from,
      subject: subject,
      snippet: '',
      body: body,
      date: DateTime(2026, 8, 6),
    );

void main() {
  group('describeSubject', () {
    test('strips reply and forward chains', () {
      expect(describeSubject('Re: Fwd: Re: Your bill is ready'),
          'Your bill is ready');
    });

    test('strips a leading bracketed tag', () {
      expect(describeSubject('[Notification] Payment received'),
          'Payment received');
      expect(describeSubject('(Automated) Order shipped'), 'Order shipped');
    });

    test('collapses runaway whitespace', () {
      expect(describeSubject('Your    bill\n\nis   ready'),
          'Your bill is ready');
    });

    test('drops a subject that only repeats the name', () {
      // A row reading "Netflix / Netflix" is worse than one with no subtitle.
      expect(describeSubject('Netflix', party: 'Netflix'), isNull);
      expect(describeSubject('  netflix  ', party: 'Netflix'), isNull);
    });

    test('keeps a subject that says more than the name', () {
      expect(
        describeSubject('Netflix — your plan renews 12 August',
            party: 'Netflix'),
        'Netflix — your plan renews 12 August',
      );
    });

    test('truncates long subjects on a word boundary', () {
      const subject =
          'Your electricity bill for the billing period of July 2026 is now '
          'available for payment through the online portal';
      final long = describeSubject(subject)!;

      expect(long.length, lessThan(82));
      expect(long, endsWith('…'));

      // Never mid-word: the kept text must be a prefix of the original that
      // ends exactly where a space does, or the row shows half a word.
      final kept = long.substring(0, long.length - 1);
      expect(subject, startsWith(kept));
      expect(subject[kept.length], ' ');
    });

    test('an empty or decoration-only subject yields nothing', () {
      expect(describeSubject('   '), isNull);
      expect(describeSubject('Re:  '), isNull);
    });
  });

  group('intermediaries are never named as the party', () {
    test('CRED becomes "via Cred", not the biller', () {
      final bill = extractBill(_mail(
        from: 'CRED <noreply@cred.club>',
        subject: 'Your bill is due',
        body: 'Amount due ₹599. Due date 12 Aug 2026.',
      ));

      expect(bill, isNotNull);
      // The row must not claim CRED is who the money is owed to.
      expect(bill!.issuer, 'via Cred');
      expect(bill.issuer, isNot('Cred'));
    });

    test('the real biller in the subject wins over the gateway', () {
      final bill = extractBill(_mail(
        from: 'Razorpay <no-reply@razorpay.com>',
        subject: 'Your Airtel bill is due',
        body: 'Amount due ₹899. Due 15 Aug 2026.',
      ));

      expect(bill, isNotNull);
      expect(bill!.issuer, 'Airtel');
    });

    test('a real biller sending directly is named directly', () {
      final bill = extractBill(_mail(
        from: 'BESCOM <billing@bescom.co.in>',
        subject: 'Electricity bill ready',
        body: 'Amount due ₹1,840. Due 12 Aug 2026.',
      ));

      expect(bill, isNotNull);
      expect(bill!.issuer, isNot(startsWith('via ')));
    });

    test('an unknown non-intermediary sender keeps its own name', () {
      final bill = extractBill(_mail(
        from: 'Billing <accounts@greenwoodhigh.edu.in>',
        subject: 'Term fee due',
        body: 'Amount due ₹42,000. Due 20 Aug 2026.',
      ));

      expect(bill, isNotNull);
      expect(bill!.issuer, isNot(startsWith('via ')));
    });
  });

  group('every row carries a description', () {
    test('a bill keeps its subject as the note', () {
      final bill = extractBill(_mail(
        from: 'CRED <noreply@cred.club>',
        subject: 'Your Vodafone bill of ₹599 is due',
        body: 'Amount due ₹599. Due 12 Aug 2026.',
      ));
      expect(bill!.note, contains('Vodafone'));
    });

    test('the bill row renders that note as its subtitle', () {
      final insight = snapshotToInsights(InsightSnapshot(
        bills: [
          Bill(
            issuer: 'via Cred',
            amount: 599,
            currency: 'INR',
            dueDate: DateTime.now().add(const Duration(days: 4)),
            lastSeen: DateTime.now(),
            sourceEmailId: 'e1',
            note: 'Your Vodafone bill of ₹599 is due',
          ),
        ],
      )).single;

      // Without this the row was a name, a number and a date — and the name was
      // the wrong company.
      expect(insight.subtitle, 'Your Vodafone bill of ₹599 is due');
    });

    test('a delivery says what shipped, not only that something did', () {
      final insight = snapshotToInsights(InsightSnapshot(
        deliveries: [
          Delivery(
            merchant: 'Amazon',
            status: DeliveryStatus.shipped,
            lastSeen: DateTime.now(),
            sourceEmailId: 'd1',
            note: 'Sony WH-1000XM5 headphones dispatched',
          ),
        ],
      )).single;

      expect(insight.subtitle, contains('Shipped'));
      expect(insight.subtitle, contains('Sony'));
    });

    test('notes survive storage', () {
      final bill = Bill(
        issuer: 'via Cred',
        amount: 599,
        currency: 'INR',
        lastSeen: DateTime(2026, 8, 6),
        sourceEmailId: 'e1',
        note: 'Your Vodafone bill',
      );
      expect(Bill.fromJson(bill.toJson()).note, 'Your Vodafone bill');
    });

    test('a snapshot from a build without notes still loads', () {
      final back = Bill.fromJson({
        'issuer': 'BESCOM',
        'amount': 100.0,
        'currency': 'INR',
        'lastSeen': DateTime(2026, 8, 6).toIso8601String(),
        'sourceEmailId': 'e1',
      });
      expect(back.note, isNull);
    });

    test('a renamed bill keeps its note', () {
      // The AI audit fixes brand names; it must not drop the description while
      // doing it.
      final bill = Bill(
        issuer: 'via Cred',
        amount: 599,
        currency: 'INR',
        lastSeen: DateTime(2026, 8, 6),
        sourceEmailId: 'e1',
        note: 'Your Vodafone bill',
      );
      expect(bill.withIssuer('Vodafone').note, 'Your Vodafone bill');
    });
  });

  group('every row can be explained', () {
    test('each insight carries the email it came from', () {
      final now = DateTime.now();
      final insights = snapshotToInsights(InsightSnapshot(
        bills: [
          Bill(
            issuer: 'BESCOM',
            amount: 100,
            currency: 'INR',
            dueDate: now.add(const Duration(days: 2)),
            lastSeen: now,
            sourceEmailId: 'bill-1',
          ),
        ],
        subscriptions: [
          Subscription(
            service: 'Netflix',
            amount: 649,
            currency: 'INR',
            cadence: Cadence.monthly,
            lastSeen: now,
            sourceEmailId: 'sub-1',
          ),
        ],
        deliveries: [
          Delivery(
            merchant: 'Amazon',
            status: DeliveryStatus.shipped,
            lastSeen: now,
            sourceEmailId: 'del-1',
          ),
        ],
        attention: [
          AttentionItem(
            title: 'Sign-in blocked',
            reason: 'Security alert',
            date: now,
            sourceEmailId: 'att-1',
          ),
        ],
      ));

      // Long-press fetches a message, so a row without its id silently cannot
      // be explained — assert every family carries one.
      expect(insights, hasLength(4));
      for (final insight in insights) {
        expect(insight.sourceEmailId, isNotNull, reason: insight.id);
        expect(insight.sourceEmailId, isNotEmpty, reason: insight.id);
      }
    });
  });
}
