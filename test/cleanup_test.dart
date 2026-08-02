/// Data-quality coverage: the rules must not claim things they don't
/// understand, and the AI audit must be able to correct what slips through.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/data/extractors/extractors.dart';
import 'package:hmail/data/mail/mail_source.dart';
import 'package:hmail/data/sync/sync_engine.dart';
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
  group('delivery precision', () {
    test('a GitHub deploy notice is not a parcel', () {
      final delivery = extractDelivery(email(
        from: 'GitHub <notifications@github.com>',
        subject: '[peersclub/hmail] Deploy shipped to production',
        body: 'Bumped the package in package.json and shipped it. '
            'Delivery of the build took 40s.',
      ));
      expect(delivery, isNull);
    });

    test('dev-tool senders never produce deliveries', () {
      for (final sender in [
        'notifications@github.com',
        'noreply@vercel.com',
        'notify@slack.com',
        'no-reply@figma.com',
      ]) {
        final delivery = extractDelivery(email(
          from: sender,
          subject: 'Your item shipped',
          body: 'The package has shipped. Tracking your order of the release.',
        ));
        expect(delivery, isNull, reason: '$sender is not a merchant');
      }
    });

    test('a real Amazon shipment still extracts', () {
      final delivery = extractDelivery(email(
        from: 'Amazon.in <shipment-tracking@amazon.in>',
        subject: 'Shipped: your order',
        body: 'Your package has shipped via Blue Dart. '
            'Tracking number: BD4459812031.',
      ));
      expect(delivery, isNotNull);
      expect(delivery!.merchant, 'Amazon');
      expect(delivery.trackingNumber, 'BD4459812031');
    });
  });

  group('applyVerdicts', () {
    final snapshot = InsightSnapshot(
      deliveries: [
        Delivery(
          merchant: 'Github',
          status: DeliveryStatus.shipped,
          lastSeen: DateTime(2026, 8, 1),
          sourceEmailId: 'gh-1',
        ),
        Delivery(
          merchant: 'Nct',
          status: DeliveryStatus.shipped,
          lastSeen: DateTime(2026, 8, 1),
          sourceEmailId: 'fk-1',
        ),
      ],
      bills: [
        Bill(
          issuer: 'Alerts',
          amount: 4200,
          currency: 'INR',
          dueDate: DateTime(2026, 8, 20),
          lastSeen: DateTime(2026, 8, 1),
          sourceEmailId: 'hdfc-1',
        ),
      ],
    );

    test('rejected insights are dropped', () {
      final cleaned = applyVerdicts(
        snapshot,
        const InsightVerdicts(rejected: {'gh-1'}),
      );
      expect(cleaned.deliveries, hasLength(1));
      expect(cleaned.deliveries.single.sourceEmailId, 'fk-1');
    });

    test('renames adopt the human brand name', () {
      final cleaned = applyVerdicts(
        snapshot,
        const InsightVerdicts(
          renamed: {'fk-1': 'Flipkart', 'hdfc-1': 'HDFC Bank'},
        ),
      );
      expect(
        cleaned.deliveries.firstWhere((d) => d.sourceEmailId == 'fk-1').merchant,
        'Flipkart',
      );
      expect(cleaned.bills.single.issuer, 'HDFC Bank');
    });

    test('renaming preserves the action links', () {
      final withLink = InsightSnapshot(deliveries: [
        Delivery(
          merchant: 'Nct',
          status: DeliveryStatus.shipped,
          trackingNumber: 'FMPP123',
          trackingUrl: 'https://ekartlogistics.com/shipmenttrack/FMPP123',
          lastSeen: DateTime(2026, 8, 1),
          sourceEmailId: 'fk-1',
        ),
      ]);
      final cleaned = applyVerdicts(
        withLink,
        const InsightVerdicts(renamed: {'fk-1': 'Flipkart'}),
      );
      final delivery = cleaned.deliveries.single;
      expect(delivery.merchant, 'Flipkart');
      expect(delivery.trackingUrl, contains('ekartlogistics'));
      expect(delivery.trackingNumber, 'FMPP123');
    });

    test('empty verdicts leave the snapshot untouched', () {
      final cleaned = applyVerdicts(snapshot, InsightVerdicts.empty);
      expect(cleaned.deliveries, hasLength(2));
      expect(cleaned.bills, hasLength(1));
      expect(identical(cleaned, snapshot), isTrue,
          reason: 'no verdicts should be a no-op, not a rebuild');
    });

    test('rejecting everything yields an empty snapshot, not a crash', () {
      final cleaned = applyVerdicts(
        snapshot,
        const InsightVerdicts(rejected: {'gh-1', 'fk-1', 'hdfc-1'}),
      );
      expect(cleaned.isEmpty, isTrue);
    });
  });

  group('date precision (regressions)', () {
    test('day-first dates keep the year written in the email', () {
      // The day group used to eat "20" of "2026", dropping the year.
      expect(extractDate('1 Aug 2026', anchor: DateTime(2026, 7, 1)),
          DateTime(2026, 8, 1));
      expect(extractDate('5 Jan 2027', anchor: DateTime(2026, 12, 1)),
          DateTime(2027, 1, 5));
    });

    test('a date meaning today does not roll a year forward', () {
      // Anchor carries a time-of-day; the candidate is midnight.
      final anchor = DateTime(2026, 8, 1, 6, 30);
      expect(extractDate('due 1 Aug', anchor: anchor), DateTime(2026, 8, 1));
      expect(extractDate('due August 1', anchor: anchor), DateTime(2026, 8, 1));
    });

    test('a genuinely past month still rolls to next year', () {
      expect(extractDate('renews on January 5', anchor: DateTime(2026, 8, 1)),
          DateTime(2027, 1, 5));
    });

    test('demo invite lands today, not next year', () async {
      final emails = await DemoMailSource().fetchCandidates();
      final invite =
          emails.firstWhere((candidate) => candidate.id == 'demo-invite');
      final event = extractEvent(invite);
      expect(event, isNotNull);
      expect(event!.start.year, DateTime.now().year);
      expect(event.isToday, isTrue);
    });
  });
}
