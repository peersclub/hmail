/// Rule-based extractors — the primary insight engine.
///
/// Machine-generated emails (receipts, bills, shipping updates) follow
/// predictable shapes, so deterministic parsing beats an LLM here: free,
/// instant, offline, and testable. The AI pass only handles what these miss.
library;

import '../../domain/models.dart';
import 'events.dart';
import 'links.dart';

export 'events.dart' show extractEvent, extractEventStart;
export 'links.dart' show extractActionUrl, extractMeetingLink;

class MoneyMatch {
  final double amount;
  final String currency;
  const MoneyMatch(this.amount, this.currency);
}

final _moneyPattern = RegExp(
  r'(₹|Rs\.?\s?|INR\s?|\$|USD\s?|€|EUR\s?|£|GBP\s?)\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

/// All plausible money amounts in [text], in order of appearance.
List<MoneyMatch> extractAllMoney(String text) {
  final matches = <MoneyMatch>[];
  for (final match in _moneyPattern.allMatches(text)) {
    final raw = match.group(2)!.replaceAll(',', '');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0 || amount > 10000000) continue;
    final symbol = match.group(1)!.trim().toUpperCase();
    final currency = switch (symbol) {
      '₹' || 'RS' || 'RS.' || 'INR' => 'INR',
      r'$' || 'USD' => 'USD',
      '€' || 'EUR' => 'EUR',
      '£' || 'GBP' => 'GBP',
      _ => 'USD',
    };
    matches.add(MoneyMatch(amount, currency));
  }
  return matches;
}

/// First plausible money amount in [text], or null.
MoneyMatch? extractMoney(String text) {
  final all = extractAllMoney(text);
  return all.isEmpty ? null : all.first;
}

/// Best amount for a bill: prefer amounts near due/total language (real
/// emails bury offers like "₹4 cashback" before the actual amount), falling
/// back to the largest amount in the email.
MoneyMatch? extractBillMoney(String hay) {
  for (final keyword in ['amount due', 'total due', 'total amount', 'due', 'payable']) {
    final index = hay.indexOf(keyword);
    if (index < 0) continue;
    final start = (index - 40).clamp(0, hay.length);
    final end = (index + 120).clamp(0, hay.length);
    final near = extractAllMoney(hay.substring(start, end));
    if (near.isNotEmpty) {
      near.sort((a, b) => b.amount.compareTo(a.amount));
      return near.first;
    }
  }
  final all = extractAllMoney(hay);
  if (all.isEmpty) return null;
  all.sort((a, b) => b.amount.compareTo(a.amount));
  return all.first;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

// The day-after-month group must not swallow the leading digits of a year:
// without (?!\d), "1 Aug 2026" reads day=20 and loses the year entirely.
final _monthNameDate = RegExp(
  r'\b(?:(\d{1,2})(?:st|nd|rd|th)?\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s*(\d{1,2}(?!\d))?(?:st|nd|rd|th)?,?\s*(\d{4})?',
  caseSensitive: false,
);
final _numericDate = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b');

/// Parses common human date shapes ("December 15", "15 Dec 2026", "12/15/2026")
/// near [anchor]; missing year resolves to the next occurrence after anchor.
DateTime? extractDate(String text, {required DateTime anchor}) {
  final numeric = _numericDate.firstMatch(text);
  if (numeric != null) {
    var year = int.parse(numeric.group(3)!);
    if (year < 100) year += 2000;
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    // Disambiguate day/month by validity; prefer day-first (common in IN/EU).
    if (a <= 31 && b <= 12) return DateTime(year, b, a);
    if (a <= 12 && b <= 31) return DateTime(year, a, b);
    return null;
  }

  final named = _monthNameDate.firstMatch(text);
  if (named != null) {
    final month = _months[named.group(2)!.toLowerCase().substring(0, 3)]!;
    final day =
        int.tryParse(named.group(1) ?? '') ?? int.tryParse(named.group(3) ?? '');
    if (day == null || day < 1 || day > 31) return null;
    var year = int.tryParse(named.group(4) ?? '') ?? anchor.year;
    var candidate = DateTime(year, month, day);
    // Compare whole days: the candidate is midnight, so an anchor later the
    // same day would otherwise push a date that means "today" a year out.
    final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
    if (named.group(4) == null && candidate.isBefore(anchorDay)) {
      candidate = DateTime(year + 1, month, day);
    }
    return candidate;
  }
  return null;
}

/// Known subscription services, keyed by sender-domain fragment.
const _subscriptionServices = <String, String>{
  'netflix': 'Netflix',
  'spotify': 'Spotify',
  'youtube': 'YouTube Premium',
  'google': 'Google',
  'apple': 'Apple',
  'icloud': 'iCloud',
  'adobe': 'Adobe',
  'openai': 'OpenAI',
  'anthropic': 'Anthropic',
  'github': 'GitHub',
  'notion': 'Notion',
  'canva': 'Canva',
  'jiohotstar': 'JioHotstar',
  'hotstar': 'Disney+ Hotstar',
  'primevideo': 'Prime Video',
  'audible': 'Audible',
  'linkedin': 'LinkedIn Premium',
  'dropbox': 'Dropbox',
  'figma': 'Figma',
  'vercel': 'Vercel',
  'railway': 'Railway',
  'jiocinema': 'JioCinema',
  'jiosaavn': 'JioSaavn',
  'sonyliv': 'SonyLIV',
  'zee5': 'Zee5',
  'amazon prime': 'Amazon Prime',
  'swiggy one': 'Swiggy One',
  'zomato gold': 'Zomato Gold',
  'timesprime': 'Times Prime',
  'times prime': 'Times Prime',
  'cult.fit': 'Cult.fit',
  'cultfit': 'Cult.fit',
  'wynk': 'Wynk Music',
  'gaana': 'Gaana',
  'microsoft365': 'Microsoft 365',
  'microsoft': 'Microsoft',
};

const _subscriptionWords = [
  'subscription', 'renewal', 'renew', 'membership', 'your plan',
  'payment successful', 'receipt', 'invoice', 'has been charged',
];

Subscription? extractSubscription(EmailMeta email) {
  final hay = email.haystack;
  if (!_subscriptionWords.any(hay.contains)) return null;

  String? service;
  for (final entry in _subscriptionServices.entries) {
    if (email.senderDomain.contains(entry.key) ||
        email.subject.toLowerCase().contains(entry.key)) {
      service = entry.value;
      break;
    }
  }
  // Unknown sender: still a subscription if the language is unambiguous.
  if (service == null &&
      (hay.contains('subscription') || hay.contains('membership'))) {
    service = _titleCaseDomain(email.senderDomain);
  }
  if (service == null || service.isEmpty) return null;

  final money = extractMoney(hay);
  if (money == null) return null;

  final cadence = hay.contains('year') || hay.contains('annual')
      ? Cadence.yearly
      : (hay.contains('month') || hay.contains('/mo'))
          ? Cadence.monthly
          : Cadence.unknown;

  return Subscription(
    service: service,
    amount: money.amount,
    currency: money.currency,
    cadence: cadence,
    nextRenewal: extractDate(hay, anchor: email.date),
    lastSeen: email.date,
    sourceEmailId: email.id,
    manageUrl: extractActionUrl(
      email,
      keywords: ['manage', 'cancel', 'billing', 'your account', 'your plan'],
      preferHosts: ['/account', '/manage', '/billing', '/subscription'],
    ),
  );
}

const _billWords = ['bill', 'due', 'statement', 'payment due', 'amount due'];
const _billIssuers = <String, String>{
  // Specific issuers come before generic words: map order decides ties, so
  // 'tatapower' must win over 'power' and 'mahanagargas' over 'gas'.
  'mahadiscom': 'MSEDCL',
  'msedcl': 'MSEDCL',
  'tatapower': 'Tata Power',
  'tata power': 'Tata Power',
  'adanielectricity': 'Adani Electricity',
  'adani electricity': 'Adani Electricity',
  'bses': 'BSES',
  'tangedco': 'TANGEDCO',
  'tneb': 'TNEB',
  'kseb': 'KSEB',
  'bwssb': 'BWSSB',
  'iglonline': 'Indraprastha Gas',
  'indraprastha': 'Indraprastha Gas',
  'mahanagargas': 'Mahanagar Gas',
  'electric': 'Electricity',
  'power': 'Electricity',
  'bescom': 'BESCOM',
  'water': 'Water',
  'gas': 'Gas',
  'jio': 'Jio',
  'airtel': 'Airtel',
  'vi.': 'Vi',
  'act': 'ACT Fibernet',
  'broadband': 'Broadband',
  'hathway': 'Hathway',
  'tataplay': 'Tata Play',
  'tata play': 'Tata Play',
  'excitel': 'Excitel',
  'hdfcergo': 'HDFC Ergo',
  'hdfc': 'HDFC Card',
  'icicilombard': 'ICICI Lombard',
  'icici': 'ICICI Card',
  'axis': 'Axis Card',
  'sbi': 'SBI Card',
  'amex': 'Amex',
  'kotak': 'Kotak Card',
  'yesbank': 'Yes Bank Card',
  'yes bank': 'Yes Bank Card',
  'idfcfirst': 'IDFC First Card',
  'idfc first': 'IDFC First Card',
  'indusind': 'IndusInd Card',
  'hsbc': 'HSBC Card',
  'citibank': 'Citi Card',
  'onecard': 'OneCard',
  'rblbank': 'RBL Card',
  'creditcard': 'Credit Card',
  'licindia': 'LIC',
  'starhealth': 'Star Health',
  'star health': 'Star Health',
};

Bill? extractBill(EmailMeta email) {
  final hay = email.haystack;
  final subject = email.subject.toLowerCase();
  if (!_billWords.any(subject.contains) && !hay.contains('amount due')) {
    return null;
  }
  // Subscription renewals also say "payment" — bills need due-language.
  if (!hay.contains('due')) return null;

  final money = extractBillMoney(hay);
  if (money == null) return null;

  // Sender domain identifies the issuer more precisely than subject words
  // ("billing@bescom.co.in" beats the generic "electricity" in the subject).
  String issuer = _titleCaseDomain(email.senderDomain);
  final domainMatch = _billIssuers.entries
      .where((entry) => email.senderDomain.contains(entry.key))
      .firstOrNull;
  if (domainMatch != null) {
    issuer = domainMatch.value;
  } else {
    for (final entry in _billIssuers.entries) {
      if (subject.contains(entry.key)) {
        issuer = entry.value;
        break;
      }
    }
  }

  // Look for the date nearest the word "due" for precision.
  final dueIndex = hay.indexOf('due');
  final window = dueIndex >= 0
      ? hay.substring(dueIndex, (dueIndex + 80).clamp(0, hay.length))
      : hay;
  final dueDate =
      extractDate(window, anchor: email.date) ?? extractDate(hay, anchor: email.date);

  return Bill(
    issuer: issuer,
    amount: money.amount,
    currency: money.currency,
    dueDate: dueDate,
    lastSeen: email.date,
    sourceEmailId: email.id,
    payUrl: extractActionUrl(
      email,
      keywords: ['pay', 'payment', 'view bill', 'quick pay'],
      preferHosts: [
        'upi://', 'billdesk', 'razorpay', 'payu', 'paytm', 'phonepe', '/pay',
      ],
    ),
  );
}

const _carriers = <String, String>{
  'bluedart': 'Blue Dart',
  'blue dart': 'Blue Dart',
  'delhivery': 'Delhivery',
  'dtdc': 'DTDC',
  'ekart': 'Ekart',
  'fedex': 'FedEx',
  'ups': 'UPS',
  'dhl': 'DHL',
  'usps': 'USPS',
  'shiprocket': 'Shiprocket',
  'xpressbees': 'XpressBees',
  'ecom express': 'Ecom Express',
  'india post': 'India Post',
  'indiapost': 'India Post',
  'shadowfax': 'Shadowfax',
};

const _merchants = <String, String>{
  'amazon': 'Amazon',
  'flipkart': 'Flipkart',
  'myntra': 'Myntra',
  'ajio': 'AJIO',
  'croma': 'Croma',
  'apple': 'Apple Store',
  'nykaa': 'Nykaa',
  'bigbasket': 'BigBasket',
  'meesho': 'Meesho',
  'jiomart': 'JioMart',
  'tatacliq': 'Tata CLiQ',
  'tata cliq': 'Tata CLiQ',
  'reliancedigital': 'Reliance Digital',
  'reliance digital': 'Reliance Digital',
  'lenskart': 'Lenskart',
  'firstcry': 'FirstCry',
  'decathlon': 'Decathlon',
  'pepperfry': 'Pepperfry',
  'blinkit': 'Blinkit',
  'zepto': 'Zepto',
  'snapdeal': 'Snapdeal',
  'instamart': 'Swiggy Instamart',
  'dmart': 'DMart Ready',
};

final _trackingPattern = RegExp(r'\b([A-Z0-9]{10,22})\b');

/// Senders that talk about shipping, packages and delivery as jargon but
/// never post a physical parcel.
const _nonCommerceSenders = [
  'github', 'gitlab', 'bitbucket', 'atlassian', 'jira', 'slack', 'notion',
  'figma', 'vercel', 'railway', 'netlify', 'linear.app', 'sentry', 'npmjs',
  'docker', 'circleci', 'asana', 'trello', 'zoom.us', 'dropbox', 'heroku',
  'cloudflare', 'stripe', 'twilio', 'sendgrid', 'mailchimp', 'substack',
  'medium.com', 'producthunt', 'openai', 'anthropic',
];

Delivery? extractDelivery(EmailMeta email) {
  final hay = email.haystack;
  final subject = email.subject.toLowerCase();

  final DeliveryStatus? status;
  if (hay.contains('out for delivery')) {
    status = DeliveryStatus.outForDelivery;
  } else if (subject.contains('delivered') || hay.contains('was delivered') || hay.contains('has been delivered')) {
    status = DeliveryStatus.delivered;
  } else if (subject.contains('shipped') ||
      subject.contains('dispatched') ||
      subject.contains('on its way') ||
      hay.contains('has shipped') ||
      hay.contains('has been shipped')) {
    status = DeliveryStatus.shipped;
  } else if (subject.contains('order confirmed') ||
      subject.contains('order placed')) {
    status = DeliveryStatus.ordered;
  } else {
    status = null;
  }
  if (status == null) return null;

  // A status word alone isn't a shipment ("we shipped dark mode" — GitHub).
  // Require commerce evidence somewhere in the email.
  const evidence = [
    'order', 'package', 'parcel', 'shipment', 'tracking', 'delivery',
    'courier', 'item', 'arriving',
  ];
  if (!evidence.any(hay.contains)) return null;

  // Evidence words aren't enough for dev/SaaS senders: "shipped", "delivery"
  // and "package" are their everyday vocabulary (a diff touching
  // package.json used to surface as a GitHub parcel). These senders never
  // ship physical goods, so drop them outright.
  if (_nonCommerceSenders.any(email.senderDomain.contains)) return null;

  String merchant = _titleCaseDomain(email.senderDomain);
  for (final entry in _merchants.entries) {
    if (email.senderDomain.contains(entry.key) || subject.contains(entry.key)) {
      merchant = entry.value;
      break;
    }
  }

  String? carrier;
  for (final entry in _carriers.entries) {
    if (hay.contains(entry.key)) {
      carrier = entry.value;
      break;
    }
  }

  // Tracking numbers: search near tracking-language only, to avoid matching
  // order IDs or hashes elsewhere in the body.
  String? tracking;
  final trackIndex = hay.indexOf('tracking');
  if (trackIndex >= 0) {
    final window = email.haystack
        .substring(trackIndex, (trackIndex + 120).clamp(0, hay.length));
    tracking = _trackingPattern
        .firstMatch(window.toUpperCase())
        ?.group(1);
  }

  DateTime? eta;
  final arrivingIndex = hay.indexOf('arriv');
  if (arrivingIndex >= 0) {
    final window =
        hay.substring(arrivingIndex, (arrivingIndex + 80).clamp(0, hay.length));
    eta = extractDate(window, anchor: email.date);
  }
  eta ??= status == DeliveryStatus.delivered
      ? null
      : extractDate(hay, anchor: email.date);

  return Delivery(
    merchant: merchant,
    carrier: carrier,
    status: status,
    trackingNumber: tracking,
    eta: eta,
    lastSeen: email.date,
    sourceEmailId: email.id,
    trackingUrl: extractActionUrl(
      email,
      keywords: ['track', 'tracking', 'shipment', 'where is my order'],
      preferHosts: [
        'bluedart', 'delhivery', 'dtdc', 'ekart', 'fedex', 'ups.com', 'dhl',
        'usps', 'shiprocket', 'aftership', 'progress-tracker', '/track',
      ],
    ),
  );
}

/// Known content senders → (kind, display source). Domain-keyed so a Substack
/// *receipt* (which says "subscription") still routes to money, while a
/// Substack *post* lands here.
const _contentSenders = <String, (FeedKind, String)>{
  'theken.com': (FeedKind.article, 'The Ken'),
  'the-ken': (FeedKind.article, 'The Ken'),
  'substack.com': (FeedKind.newsletter, 'Substack'),
  'medium.com': (FeedKind.article, 'Medium'),
  'nytimes.com': (FeedKind.article, 'The New York Times'),
  'economist.com': (FeedKind.article, 'The Economist'),
  'stratechery.com': (FeedKind.article, 'Stratechery'),
  'morningbrew.com': (FeedKind.newsletter, 'Morning Brew'),
  'finshots': (FeedKind.newsletter, 'Finshots'),
  'youtube.com': (FeedKind.video, 'YouTube'),
  'youtube-noreply': (FeedKind.video, 'YouTube'),
  'spotify.com': (FeedKind.podcast, 'Spotify'),
  'anchor.fm': (FeedKind.podcast, 'Spotify Podcasts'),
  'apple.com/podcast': (FeedKind.podcast, 'Apple Podcasts'),
};

/// Words that signal "here's content to consume" for unknown senders.
const _contentSignals = [
  'new post', 'new article', 'new issue', 'new edition', 'just published',
  'uploaded', 'new video', 'new episode', 'read now', 'this week',
  'your digest', 'weekly digest', 'newsletter',
];

/// Senders whose "new post"-style mail is transactional, not content.
const _notContentSenders = [
  'github', 'gitlab', 'jira', 'atlassian', 'linkedin', 'twitter', 'x.com',
  'facebook', 'instagram', 'quora', 'reddit', 'stackoverflow',
];

FeedItem? extractFeed(EmailMeta email) {
  final domain = email.senderDomain;
  final hay = email.haystack;

  (FeedKind, String)? match;
  for (final entry in _contentSenders.entries) {
    if (domain.contains(entry.key)) {
      match = entry.value;
      break;
    }
  }

  // Unknown sender: only claim it as content on clear language, and never for
  // the social/dev senders whose notifications merely sound content-like.
  if (match == null) {
    if (_notContentSenders.any(domain.contains)) return null;
    if (!_contentSignals.any(hay.contains)) return null;
    match = (FeedKind.newsletter, _titleCaseDomain(domain));
  }

  final (kind, source) = match;
  final title = _cleanFeedTitle(email.subject, source);
  if (title.isEmpty) return null;

  return FeedItem(
    kind: kind,
    source: source,
    title: title,
    url: extractActionUrl(
      email,
      keywords: ['read', 'watch', 'listen', 'view', 'open', 'continue'],
    ),
    date: email.date,
    lastSeen: email.date,
    sourceEmailId: email.id,
  );
}

/// Strips publisher boilerplate from a subject so the title reads cleanly:
/// "New post: X" → "X", "Channel uploaded: X" → "X".
String _cleanFeedTitle(String subject, String source) {
  var title = subject.trim();
  final patterns = [
    RegExp(r'^new (post|article|issue|edition|video|episode)\s*[:\-–]\s*',
        caseSensitive: false),
    RegExp(r'^.*?\buploaded\b\s*[:\-–]?\s*', caseSensitive: false),
    RegExp(r'^just published\s*[:\-–]?\s*', caseSensitive: false),
    RegExp(r'^\[.*?\]\s*'),
  ];
  for (final pattern in patterns) {
    title = title.replaceFirst(pattern, '');
  }
  return title.trim();
}

const _attentionSignals = [
  'security alert', 'unrecognized device', 'suspicious', 'verify your',
  'password', 'action required', 'expires', 'deadline', 'appointment',
  'last chance to respond', 'account suspended',
];

/// Heuristic attention pass over unclaimed emails — catches the obvious
/// must-see items without AI; an AI gateway can replace these with better ones.
List<AttentionItem> extractAttention(List<EmailMeta> unclaimed) {
  final items = <AttentionItem>[];
  for (final email in unclaimed) {
    final hay = email.haystack;
    if (_attentionSignals.any(hay.contains)) {
      items.add(AttentionItem(
        title: email.subject.isEmpty ? 'Needs review' : email.subject,
        reason: email.snippet.isEmpty ? email.from : email.snippet,
        date: email.date,
        sourceEmailId: email.id,
        linkUrl: extractActionUrl(
          email,
          keywords: [
            'verify', 'review', 'reset', 'sign in', 'respond', 'confirm',
            'secure', 'view',
          ],
        ),
      ));
    }
  }
  items.sort((a, b) => b.date.compareTo(a.date));
  return items.take(5).toList();
}

String _titleCaseDomain(String domain) {
  final base = domain.split('.').firstWhere(
        (part) => part.isNotEmpty && part != 'mail' && part != 'email' && part != 'no-reply',
        orElse: () => domain,
      );
  if (base.isEmpty) return domain;
  return base[0].toUpperCase() + base.substring(1);
}

/// Runs every extractor over [emails]; returns extracted insights plus the
/// emails nothing claimed (candidates for the AI attention pass).
({
  List<Subscription> subscriptions,
  List<Bill> bills,
  List<Delivery> deliveries,
  List<EventItem> events,
  List<FeedItem> feed,
  List<EmailMeta> unclaimed,
}) runExtractors(List<EmailMeta> emails) {
  final subscriptions = <Subscription>[];
  final bills = <Bill>[];
  final deliveries = <Delivery>[];
  final events = <EventItem>[];
  final feed = <FeedItem>[];
  final unclaimed = <EmailMeta>[];

  for (final email in emails) {
    // Events first: invite emails are the most distinctively shaped, and
    // "Invitation: Budget review @ ..." must not be misread as a bill.
    final event = extractEvent(email);
    if (event != null) {
      events.add(event);
      continue;
    }
    final delivery = extractDelivery(email);
    if (delivery != null) {
      deliveries.add(delivery);
      continue;
    }
    final bill = extractBill(email);
    if (bill != null) {
      bills.add(bill);
      continue;
    }
    // Money before feed: a Substack *receipt* is a subscription, not a read.
    final subscription = extractSubscription(email);
    if (subscription != null) {
      subscriptions.add(subscription);
      continue;
    }
    final feedItem = extractFeed(email);
    if (feedItem != null) {
      feed.add(feedItem);
      continue;
    }
    unclaimed.add(email);
  }

  return (
    subscriptions: subscriptions,
    bills: bills,
    deliveries: deliveries,
    events: events,
    feed: feed,
    unclaimed: unclaimed,
  );
}
