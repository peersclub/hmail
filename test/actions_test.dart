import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/extractors/extractors.dart';
import 'package:hmail/domain/actions.dart';
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
  group('extractActionUrl', () {
    test('picks the link next to action language, not the first link', () {
      final url = extractActionUrl(
        email(
          body: 'Big sale! https://amzn.example.com/deals\n\n'
              'Track your package here: https://www.delhivery.com/track/package/AWB123',
        ),
        keywords: ['track'],
      );
      expect(url, 'https://www.delhivery.com/track/package/AWB123');
    });

    test('prefers a upi:// intent for payments', () {
      final url = extractActionUrl(
        email(
          body: 'Pay your bill: https://biller.example.com/pay\n'
              'Or pay instantly: upi://pay?pa=bescom@icici&am=1840.50',
        ),
        keywords: ['pay'],
      );
      expect(url, startsWith('upi://pay?'));
    });

    test('ignores unsubscribe and social links', () {
      final url = extractActionUrl(
        email(
          body: 'Follow us https://facebook.com/brand\n'
              'https://example.com/unsubscribe?u=1',
        ),
        keywords: ['track'],
      );
      expect(url, isNull);
    });

    test('rejects bare unrelated links below the confidence floor', () {
      final url = extractActionUrl(
        email(body: 'Read our blog https://blog.example.com/post/123456'),
        keywords: ['pay'],
      );
      expect(url, isNull);
    });
  });

  group('actionsForDelivery', () {
    test('prefers the tracking link from the email itself', () {
      final delivery = Delivery(
        merchant: 'Amazon',
        carrier: 'Delhivery',
        status: DeliveryStatus.shipped,
        trackingNumber: 'AWB123',
        trackingUrl: 'https://www.delhivery.com/track/package/AWB123',
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-1',
      );
      final actions = actionsForDelivery(delivery);
      expect(actions.first.kind, ActionKind.track);
      expect(actions.first.uri.host, 'www.delhivery.com');
      expect(actions.last.kind, ActionKind.openEmail);
    });

    test('falls back to a carrier template from the tracking number', () {
      final delivery = Delivery(
        merchant: 'Flipkart',
        carrier: 'FedEx',
        status: DeliveryStatus.shipped,
        trackingNumber: '123456789012',
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-2',
      );
      final actions = actionsForDelivery(delivery);
      expect(actions.first.uri.toString(),
          'https://www.fedex.com/fedextrack/?trknbr=123456789012');
    });

    test('unknown carrier falls back to the universal tracker', () {
      final delivery = Delivery(
        merchant: 'Nykaa',
        carrier: 'DTDC',
        status: DeliveryStatus.shipped,
        trackingNumber: 'D1234567',
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-3',
      );
      final actions = actionsForDelivery(delivery);
      expect(actions.first.uri.host, 't.17track.net');
    });

    test('no link and no number still yields Open email', () {
      final delivery = Delivery(
        merchant: 'Croma',
        status: DeliveryStatus.ordered,
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-4',
      );
      final actions = actionsForDelivery(delivery);
      expect(actions, hasLength(1));
      expect(actions.single.kind, ActionKind.openEmail);
    });
  });

  group('actionsForBill', () {
    test('upi link gets a UPI label; reminder lands on the due date', () {
      final bill = Bill(
        issuer: 'BESCOM',
        amount: 1840.50,
        currency: 'INR',
        dueDate: DateTime(2099, 8, 10),
        payUrl: 'upi://pay?pa=bescom@icici&am=1840.50',
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-5',
      );
      final actions = actionsForBill(bill);
      expect(actions[0].label, 'Pay via UPI');
      expect(actions[0].uri.scheme, 'upi');
      expect(actions[1].kind, ActionKind.remind);
      expect(actions[1].uri.toString(), contains('20990810/20990811'));
      expect(actions.last.kind, ActionKind.openEmail);
    });
  });

  group('actionsForSubscription', () {
    test('known service gets its manage page without an email link', () {
      final sub = Subscription(
        service: 'Netflix',
        amount: 649,
        currency: 'INR',
        cadence: Cadence.monthly,
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-6',
      );
      final actions = actionsForSubscription(sub);
      expect(actions.first.uri.toString(), 'https://www.netflix.com/account');
    });
  });

  group('actionsForEvent', () {
    test('join link first, then calendar day, then email', () {
      final event = EventItem(
        title: 'Design sync',
        start: DateTime(2026, 8, 3, 15),
        meetingUrl: 'https://meet.google.com/abc-defg-hij',
        provider: MeetingProvider.meet,
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-7',
      );
      final actions = actionsForEvent(event);
      expect(actions[0].label, 'Join on Meet');
      expect(actions[1].uri.toString(),
          'https://calendar.google.com/calendar/r/day/2026/8/3');
      expect(actions[2].kind, ActionKind.openEmail);
    });

    test('cancelled events do not offer a join action', () {
      final event = EventItem(
        title: 'Design sync',
        start: DateTime(2026, 8, 3, 15),
        meetingUrl: 'https://meet.google.com/abc-defg-hij',
        isCancelled: true,
        lastSeen: DateTime(2026, 8, 1),
        sourceEmailId: 'em-8',
      );
      final kinds = actionsForEvent(event).map((a) => a.kind);
      expect(kinds, isNot(contains(ActionKind.join)));
    });
  });

  group('extractEvent', () {
    test('parses a Google Calendar invite subject', () {
      final event = extractEvent(email(
        from: 'Priya Sharma <priya@company.com>',
        subject:
            'Invitation: Design sync @ Mon Aug 3, 2026 3pm - 3:30pm (IST) (victor@x.com)',
        body: 'When: Mon Aug 3, 2026 3pm – 3:30pm India Standard Time\n'
            'Joining info: https://meet.google.com/abc-defg-hij',
      ));
      expect(event, isNotNull);
      expect(event!.title, 'Design sync');
      expect(event.start, DateTime(2026, 8, 3, 15));
      expect(event.end, DateTime(2026, 8, 3, 15, 30));
      expect(event.organizer, 'Priya Sharma');
      expect(event.provider, MeetingProvider.meet);
      expect(event.isCancelled, isFalse);
    });

    test('parses a Zoom invite from the body', () {
      final event = extractEvent(email(
        from: 'Rahul <rahul@vendor.com>',
        subject: 'Quarterly review',
        body: 'Rahul is inviting you to a scheduled Zoom meeting.\n'
            'Time: Aug 5, 2026 11:00 AM India\n'
            'Join Zoom Meeting\nhttps://us02web.zoom.us/j/89123456789?pwd=abc',
      ));
      expect(event, isNotNull);
      expect(event!.start, DateTime(2026, 8, 5, 11));
      expect(event.provider, MeetingProvider.zoom);
    });

    test('flags cancelled events', () {
      final event = extractEvent(email(
        subject: 'Canceled event: Design sync @ Mon Aug 3, 2026 3pm (IST)',
        body: 'This event has been canceled.',
      ));
      expect(event, isNotNull);
      expect(event!.isCancelled, isTrue);
    });

    test('ignores a newsletter that merely mentions a webinar', () {
      final event = extractEvent(email(
        subject: 'Your weekly product digest',
        body: 'Top stories this week... nothing to see here.',
      ));
      expect(event, isNull);
    });

    test('event dedupes across update emails', () {
      final first = extractEvent(email(
        id: 'a',
        subject: 'Invitation: Standup @ Mon Aug 3, 2026 10am (IST)',
        body: 'When: Mon Aug 3, 2026 10am',
      ));
      final second = extractEvent(email(
        id: 'b',
        subject: 'Updated invitation: Standup @ Mon Aug 3, 2026 10am (IST)',
        body: 'When: Mon Aug 3, 2026 10am',
      ));
      expect(first!.dedupeKey, second!.dedupeKey);
    });
  });

  group('runExtractors', () {
    test('claims invites as events, not bills', () {
      final result = runExtractors([
        email(
          subject: 'Invitation: Budget review @ Mon Aug 3, 2026 3pm (IST)',
          body: 'When: Mon Aug 3, 2026 3pm\nAmount due discussion ₹5,000',
        ),
      ]);
      expect(result.events, hasLength(1));
      expect(result.bills, isEmpty);
    });
  });
}
