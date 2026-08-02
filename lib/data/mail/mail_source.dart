import '../../domain/models.dart';

/// A backend that yields candidate emails for insight extraction.
///
/// Gmail is the production implementation; [DemoMailSource] feeds the same
/// pipeline with fixture emails, so demo mode exercises the real extractors
/// rather than rendering canned results.
abstract interface class MailSource {
  Future<List<EmailMeta>> fetchCandidates();
}

class DemoMailSource implements MailSource {
  @override
  Future<List<EmailMeta>> fetchCandidates() async {
    final now = DateTime.now();
    String day(DateTime date) =>
        '${date.day} ${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.month - 1]} ${date.year}';
    String clock(DateTime date) {
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      return '$hour${date.hour < 12 ? 'am' : 'pm'}';
    }

    return [
      EmailMeta(
        id: 'demo-netflix',
        from: 'Netflix <info@mailer.netflix.com>',
        subject: 'Your Netflix subscription renewal',
        snippet: 'Your plan renews soon.',
        body:
            'Your monthly plan renews on ${day(now.add(const Duration(days: 9)))} for ₹649.',
        date: now.subtract(const Duration(days: 21)),
      ),
      EmailMeta(
        id: 'demo-spotify',
        from: 'Spotify <no-reply@spotify.com>',
        subject: 'Receipt for your Premium subscription',
        snippet: 'Payment successful.',
        body:
            'Payment successful: ₹119 monthly. Next billing date ${day(now.add(const Duration(days: 14)))}.',
        date: now.subtract(const Duration(days: 16)),
      ),
      EmailMeta(
        id: 'demo-adobe',
        from: 'Adobe <mail@mail.adobe.com>',
        subject: 'Your Adobe invoice',
        snippet: 'Thanks for your subscription payment.',
        body:
            'Invoice: Creative Cloud subscription ₹4,230 per month. Renews ${day(now.add(const Duration(days: 4)))}.',
        date: now.subtract(const Duration(days: 26)),
      ),
      EmailMeta(
        id: 'demo-icloud',
        from: 'Apple <no_reply@email.apple.com>',
        subject: 'Receipt for your iCloud+ subscription',
        snippet: 'Annual plan receipt.',
        body: 'iCloud+ annual plan: ₹999 per year.',
        date: now.subtract(const Duration(days: 175)),
      ),
      EmailMeta(
        id: 'demo-bescom',
        from: 'BESCOM <billing@bescom.co.in>',
        subject: 'Electricity bill for last month',
        snippet: 'Your bill is ready.',
        body:
            'Amount due: ₹1,840. Payment due by ${day(now.add(const Duration(days: 6)))}. '
            'Pay instantly: upi://pay?pa=bescom@icici&pn=BESCOM&am=1840&cu=INR',
        date: now.subtract(const Duration(days: 2)),
      ),
      EmailMeta(
        id: 'demo-act',
        from: 'ACT Fibernet <bill@actcorp.in>',
        subject: 'Your broadband bill is due',
        snippet: 'Bill generated.',
        body:
            'Amount due ₹1,180.82 by ${day(now.add(const Duration(days: 3)))}.',
        date: now.subtract(const Duration(days: 4)),
      ),
      EmailMeta(
        id: 'demo-hdfc',
        from: 'HDFC Bank <alerts@hdfcbank.net>',
        subject: 'Credit card statement — payment due',
        snippet: 'Statement ready.',
        body:
            'Total amount due ₹42,350.19. Due date: ${day(now.add(const Duration(days: 11)))}.',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-amazon',
        from: 'Amazon.in <shipment-tracking@amazon.in>',
        subject: 'Out for delivery: your package',
        snippet: 'Arriving today.',
        body:
            'Your package is out for delivery. Tracking number: BD4459812031 via Blue Dart. Arriving ${day(now)}. '
            'Track your package: https://www.amazon.in/progress-tracker/package/demo',
        date: now.subtract(const Duration(hours: 3)),
      ),
      EmailMeta(
        id: 'demo-flipkart',
        from: 'Flipkart <noreply@nct.flipkart.com>',
        subject: 'Shipped: your order',
        snippet: 'On the way.',
        body:
            'Your order has been shipped via Ekart. Arriving ${day(now.add(const Duration(days: 2)))}.',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-croma',
        from: 'Croma <orders@croma.com>',
        subject: 'Delivered: your order',
        snippet: 'Delivered.',
        body: 'Your order was delivered on ${day(now.subtract(const Duration(days: 3)))}.',
        date: now.subtract(const Duration(days: 3)),
      ),
      EmailMeta(
        id: 'demo-return',
        from: 'Myntra <orders@myntra.com>',
        subject: 'Your order was delivered',
        snippet: 'Delivered — returns are open.',
        body:
            'Your order was delivered. Not a perfect fit? Eligible for return by '
            '${day(now.add(const Duration(days: 7)))}. '
            'Start a return: https://www.myntra.com/my/returns',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-warranty',
        from: 'boAt <care@boat-lifestyle.com>',
        subject: 'Your product warranty',
        snippet: 'Warranty details inside.',
        body:
            'Thanks for registering your Airdopes. Warranty valid until '
            '${day(now.add(const Duration(days: 40)))}. '
            'View warranty: https://www.boat-lifestyle.com/warranty',
        date: now.subtract(const Duration(days: 20)),
      ),
      // Always ~2h in the future so the demo Today screen has a joinable
      // meeting no matter when it's opened.
      EmailMeta(
        id: 'demo-invite',
        from: 'Priya Sharma <priya@peersclub.com>',
        subject:
            'Invitation: Product sync @ ${day(now.add(const Duration(hours: 2)))} ${clock(now.add(const Duration(hours: 2)))} (IST) (you)',
        snippet: 'You have been invited.',
        body:
            'When: ${day(now.add(const Duration(hours: 2)))} ${clock(now.add(const Duration(hours: 2)))} India Standard Time\n'
            'Joining info: https://meet.google.com/abc-defg-hij\n'
            'Where: Google Meet',
        date: now.subtract(const Duration(hours: 20)),
      ),
      EmailMeta(
        id: 'demo-failed',
        from: 'Netflix <info@mailer.netflix.com>',
        subject: 'Your payment was declined',
        snippet: 'Update your payment method.',
        body:
            'Payment failed: we could not process your ₹649 payment. Update payment method: https://netflix.com/account/payment',
        date: now.subtract(const Duration(hours: 8)),
      ),
      EmailMeta(
        id: 'demo-refund',
        from: 'Amazon.in <auto-confirm@amazon.in>',
        subject: 'Your refund has been processed',
        snippet: 'Refund initiated.',
        body:
            'Refund of ₹1,299 has been refunded to your original payment method for order 402-1234.',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-github',
        from: 'GitHub <noreply@github.com>',
        subject: 'Security alert: new sign-in from an unrecognized device',
        snippet: 'Review this sign-in.',
        body:
            'A new sign-in to your account was detected from an unrecognized device. If this wasn\'t you, secure your account.',
        date: now.subtract(const Duration(hours: 6)),
      ),
      EmailMeta(
        id: 'demo-psk',
        from: 'Passport Seva <donotreply@passportindia.gov.in>',
        subject: 'Appointment confirmation pending — action required',
        snippet: 'Pick a slot.',
        body:
            'Your passport renewal application requires you to book an appointment slot within 7 days or the application expires.',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-ken',
        from: 'The Ken <newsletters@theken.com>',
        subject: 'The great Indian quick-commerce shakeout',
        snippet: 'Read now.',
        body:
            'Your daily story is live. Read now: https://the-ken.com/story/quick-commerce-shakeout',
        date: now.subtract(const Duration(hours: 5)),
      ),
      EmailMeta(
        id: 'demo-substack',
        from: "Lenny's Newsletter <lenny@substack.com>",
        subject: 'New post: How the best PMs run discovery',
        snippet: 'A new issue.',
        body:
            'A new issue just landed. Read it here: https://lennysnewsletter.com/p/discovery',
        date: now.subtract(const Duration(days: 1)),
      ),
      EmailMeta(
        id: 'demo-flight',
        from: 'IndiGo <noreply@goindigo.in>',
        subject: 'Your e-ticket — BLR to DEL, PNR X4K9Q2',
        snippet: 'Booking confirmed.',
        body:
            'Booking confirmed. PNR: X4K9Q2. Departure BLR → DEL on ${day(now.add(const Duration(days: 2)))}. Web check-in opens 48 hours before departure: https://goindigo.in/web-check-in',
        date: now.subtract(const Duration(days: 6)),
      ),
      EmailMeta(
        id: 'demo-yt',
        from: 'YouTube <noreply@youtube.com>',
        subject: 'Veritasium uploaded: The riddle that fooled Einstein',
        snippet: 'New video.',
        body:
            'A channel you subscribe to posted a new video. Watch: https://youtube.com/watch?v=xyz',
        date: now.subtract(const Duration(days: 2)),
      ),
    ];
  }
}
