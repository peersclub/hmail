/// Domain models for NoMail.
///
/// Everything the UI renders is one of these insight types. Raw email never
/// reaches the UI layer — Gmail is a backend, not a surface.
library;

/// Minimal projection of a Gmail message used by extractors.
class EmailMeta {
  final String id;
  final String from;
  final String subject;
  final String snippet;
  final String body;
  final DateTime date;

  const EmailMeta({
    required this.id,
    required this.from,
    required this.subject,
    required this.snippet,
    required this.body,
    required this.date,
  });

  String get senderDomain {
    final match = RegExp(r'@([A-Za-z0-9.-]+)').firstMatch(from);
    return (match?.group(1) ?? '').toLowerCase();
  }

  String get haystack => '$subject\n$snippet\n$body'.toLowerCase();

  /// Original-case text for URL extraction — links carry case-sensitive
  /// tokens that [haystack]'s lowercasing would corrupt.
  String get rawText => '$subject\n$snippet\n$body';
}

enum Cadence { monthly, yearly, unknown }

class Subscription {
  final String service;
  final double amount;
  final String currency;
  final Cadence cadence;
  final DateTime? nextRenewal;
  final DateTime lastSeen;
  final String sourceEmailId;

  /// Manage/cancel link captured from the email, when one was present.
  final String? manageUrl;

  /// What the email said this was — see [Bill.note].
  final String? note;

  const Subscription({
    required this.service,
    required this.amount,
    required this.currency,
    required this.cadence,
    this.nextRenewal,
    required this.lastSeen,
    required this.sourceEmailId,
    this.manageUrl,
    this.note,
  });

  double get monthlyAmount =>
      cadence == Cadence.yearly ? amount / 12.0 : amount;

  Subscription withService(String name) => Subscription(
        service: name,
        amount: amount,
        currency: currency,
        cadence: cadence,
        nextRenewal: nextRenewal,
        lastSeen: lastSeen,
        sourceEmailId: sourceEmailId,
        manageUrl: manageUrl,
        note: note,
      );

  String get dedupeKey => service.toLowerCase();

  Map<String, dynamic> toJson() => {
        'service': service,
        'amount': amount,
        'currency': currency,
        'cadence': cadence.name,
        'nextRenewal': nextRenewal?.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'manageUrl': manageUrl,
        'note': note,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        service: json['service'] as String,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String,
        cadence: Cadence.values.firstWhere(
          (c) => c.name == json['cadence'],
          orElse: () => Cadence.unknown,
        ),
        nextRenewal: json['nextRenewal'] == null
            ? null
            : DateTime.parse(json['nextRenewal'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        manageUrl: json['manageUrl'] as String?,
        note: json['note'] as String?,
      );
}

class Bill {
  final String issuer;
  final double amount;
  final String currency;
  final DateTime? dueDate;
  final DateTime lastSeen;
  final String sourceEmailId;

  /// Direct pay link from the email — a biller payment page or a upi:// intent.
  final String? payUrl;

  /// One short line saying what this actually is, taken from the email's own
  /// subject.
  ///
  /// A bill row used to show a name, an amount and a date and nothing else,
  /// which is unreadable the moment the name is an intermediary: "CRED · ₹599 ·
  /// Due Tuesday" tells you nothing, because CRED is never the biller. The
  /// subject line is the one description the sender wrote themselves, so it is
  /// both the cheapest and the most honest thing to show.
  final String? note;

  const Bill({
    required this.issuer,
    required this.amount,
    required this.currency,
    this.dueDate,
    required this.lastSeen,
    required this.sourceEmailId,
    this.payUrl,
    this.note,
  });

  Bill withIssuer(String name) => Bill(
        issuer: name,
        amount: amount,
        currency: currency,
        dueDate: dueDate,
        lastSeen: lastSeen,
        sourceEmailId: sourceEmailId,
        payUrl: payUrl,
        note: note,
      );

  int? get _daysUntilDue {
    if (dueDate == null) return null;
    final now = DateTime.now();
    return DateTime(dueDate!.year, dueDate!.month, dueDate!.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  /// Date-based: due *today* is not overdue.
  bool get isOverdue => (_daysUntilDue ?? 1) < 0;

  bool dueWithin(Duration window) {
    final days = _daysUntilDue;
    return days != null && days >= 0 && days <= window.inDays;
  }

  /// Bills long past due were almost certainly paid — age them out of the UI.
  bool get isStale => (_daysUntilDue ?? 0) < -21;

  String get dedupeKey {
    final day = dueDate == null
        ? 'na'
        : '${dueDate!.year}-${dueDate!.month}-${dueDate!.day}';
    return '${issuer.toLowerCase()}|$day|${amount.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() => {
        'issuer': issuer,
        'amount': amount,
        'currency': currency,
        'dueDate': dueDate?.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'payUrl': payUrl,
        'note': note,
      };

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        issuer: json['issuer'] as String,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String,
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.parse(json['dueDate'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        payUrl: json['payUrl'] as String?,
        note: json['note'] as String?,
      );
}

enum DeliveryStatus { ordered, shipped, outForDelivery, delivered }

class Delivery {
  final String merchant;
  final String? carrier;
  final DeliveryStatus status;
  final String? trackingNumber;
  final DateTime? eta;
  final DateTime lastSeen;
  final String sourceEmailId;

  /// Tracking link lifted straight from the email — always preferred over a
  /// carrier URL template because it lands on the exact shipment page.
  final String? trackingUrl;

  /// What the email said this was — see [Bill.note]. "Shipped" alone does not
  /// say *what* shipped.
  final String? note;

  const Delivery({
    required this.merchant,
    this.carrier,
    required this.status,
    this.trackingNumber,
    this.eta,
    required this.lastSeen,
    required this.sourceEmailId,
    this.trackingUrl,
    this.note,
  });

  bool get isActive => status != DeliveryStatus.delivered && !isStale;

  Delivery withMerchant(String name) => Delivery(
        merchant: name,
        carrier: carrier,
        status: status,
        trackingNumber: trackingNumber,
        eta: eta,
        lastSeen: lastSeen,
        sourceEmailId: sourceEmailId,
        trackingUrl: trackingUrl,
        note: note,
      );

  /// An ETA more than a day in the past means it almost certainly arrived —
  /// stop showing it as incoming.
  bool get isStale {
    if (eta == null) {
      return lastSeen
          .isBefore(DateTime.now().subtract(const Duration(days: 14)));
    }
    return eta!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  }

  String get dedupeKey =>
      trackingNumber ?? '${merchant.toLowerCase()}|${lastSeen.toIso8601String().substring(0, 10)}';

  Map<String, dynamic> toJson() => {
        'merchant': merchant,
        'carrier': carrier,
        'status': status.name,
        'trackingNumber': trackingNumber,
        'eta': eta?.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'trackingUrl': trackingUrl,
        'note': note,
      };

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
        merchant: json['merchant'] as String,
        carrier: json['carrier'] as String?,
        status: DeliveryStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => DeliveryStatus.ordered,
        ),
        trackingNumber: json['trackingNumber'] as String?,
        eta: json['eta'] == null ? null : DateTime.parse(json['eta'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        trackingUrl: json['trackingUrl'] as String?,
        note: json['note'] as String?,
      );
}

enum MeetingProvider { meet, zoom, teams, webex, other }

/// A calendar event or meeting invite surfaced from email.
class EventItem {
  final String title;
  final String? organizer;
  final DateTime start;
  final DateTime? end;
  final String? meetingUrl;
  final MeetingProvider provider;
  final String? location;
  final bool isCancelled;
  final DateTime lastSeen;
  final String sourceEmailId;

  const EventItem({
    required this.title,
    this.organizer,
    required this.start,
    this.end,
    this.meetingUrl,
    this.provider = MeetingProvider.other,
    this.location,
    this.isCancelled = false,
    required this.lastSeen,
    required this.sourceEmailId,
  });

  bool get isToday {
    final now = DateTime.now();
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  bool get isUpcoming => !isCancelled && start.isAfter(DateTime.now());

  /// Same title + same start time = same event, however many update emails
  /// Google Calendar sends about it.
  String get dedupeKey =>
      '${title.toLowerCase().trim()}|${start.toIso8601String()}';

  Map<String, dynamic> toJson() => {
        'title': title,
        'organizer': organizer,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'meetingUrl': meetingUrl,
        'provider': provider.name,
        'location': location,
        'isCancelled': isCancelled,
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
      };

  factory EventItem.fromJson(Map<String, dynamic> json) => EventItem(
        title: json['title'] as String,
        organizer: json['organizer'] as String?,
        start: DateTime.parse(json['start'] as String),
        end: json['end'] == null ? null : DateTime.parse(json['end'] as String),
        meetingUrl: json['meetingUrl'] as String?,
        provider: MeetingProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => MeetingProvider.other,
        ),
        location: json['location'] as String?,
        isCancelled: (json['isCancelled'] ?? false) as bool,
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
      );
}

enum FeedKind { article, video, podcast, newsletter }

/// Content waiting to be consumed — a paid article (The Ken, Substack), a new
/// YouTube upload, a podcast episode, a newsletter issue. Email isn't only
/// money and parcels; a lot of it is a reading queue you never get to.
class FeedItem {
  final FeedKind kind;

  /// Publication, channel, or author — "The Ken", "Lenny's Newsletter".
  final String source;
  final String title;
  final String? url;
  final DateTime date;
  final DateTime lastSeen;
  final String sourceEmailId;

  const FeedItem({
    required this.kind,
    required this.source,
    required this.title,
    this.url,
    required this.date,
    required this.lastSeen,
    required this.sourceEmailId,
  });

  /// Same source + same title = the same piece, however many nudge emails
  /// ("you haven't read this yet") the publisher sends.
  String get dedupeKey =>
      '${source.toLowerCase().trim()}|${title.toLowerCase().trim()}';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'source': source,
        'title': title,
        'url': url,
        'date': date.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
      };

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        kind: FeedKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => FeedKind.article,
        ),
        source: json['source'] as String,
        title: json['title'] as String,
        url: json['url'] as String?,
        date: DateTime.parse(json['date'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
      );
}

enum ReturnKind { returnWindow, warranty }

/// A closing return window or an expiring warranty — money you can still get
/// back or protection about to lapse, both of which quietly expire in the
/// inbox. Anchored on [deadline] so a window about to close rises on Today.
class ReturnItem {
  final ReturnKind kind;
  final String merchant;
  final String? item;
  final DateTime deadline;
  final DateTime lastSeen;
  final String sourceEmailId;
  final String? url;

  const ReturnItem({
    required this.kind,
    required this.merchant,
    this.item,
    required this.deadline,
    required this.lastSeen,
    required this.sourceEmailId,
    this.url,
  });

  /// Once the deadline has passed there's nothing to act on.
  bool get isStale =>
      deadline.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  String get dedupeKey =>
      '${kind.name}|${merchant.toLowerCase()}|${item?.toLowerCase() ?? ''}|'
      '${deadline.toIso8601String().substring(0, 10)}';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'merchant': merchant,
        'item': item,
        'deadline': deadline.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'url': url,
      };

  factory ReturnItem.fromJson(Map<String, dynamic> json) => ReturnItem(
        kind: ReturnKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ReturnKind.returnWindow,
        ),
        merchant: json['merchant'] as String,
        item: json['item'] as String?,
        deadline: DateTime.parse(json['deadline'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        url: json['url'] as String?,
      );
}

enum PaymentKind { refund, failed }

/// Money in motion that needs attention: a refund you should confirm landed,
/// or a payment that failed and needs fixing (a declined card, a failed
/// autopay). Higher stakes than a scheduled bill — money lost vs. money due.
class PaymentAlert {
  final PaymentKind kind;
  final String source;
  final double? amount;
  final String currency;
  final DateTime date;
  final DateTime lastSeen;
  final String sourceEmailId;
  final String? actionUrl;

  const PaymentAlert({
    required this.kind,
    required this.source,
    this.amount,
    this.currency = 'INR',
    required this.date,
    required this.lastSeen,
    required this.sourceEmailId,
    this.actionUrl,
  });

  /// Resolved alerts age out after three weeks.
  bool get isStale =>
      date.isBefore(DateTime.now().subtract(const Duration(days: 21)));

  String get dedupeKey =>
      '${kind.name}|${source.toLowerCase()}|${amount?.toStringAsFixed(2) ?? ''}';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'source': source,
        'amount': amount,
        'currency': currency,
        'date': date.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'actionUrl': actionUrl,
      };

  factory PaymentAlert.fromJson(Map<String, dynamic> json) => PaymentAlert(
        kind: PaymentKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => PaymentKind.refund,
        ),
        source: json['source'] as String,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: (json['currency'] ?? 'INR') as String,
        date: DateTime.parse(json['date'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        actionUrl: json['actionUrl'] as String?,
      );
}

enum TravelKind { flight, train, hotel, bus, cab }

/// A trip surfaced from email — a flight, hotel, train, or booking. The
/// pressing moment is departure/check-in, which the ranker reads off
/// [departure]; check-in for flights opens ~48h before, so a flight inside
/// that window naturally rises on Today.
class TravelItem {
  final TravelKind kind;

  /// Airline, hotel, or booking provider — "IndiGo", "MakeMyTrip".
  final String provider;

  /// Route or place — "BLR → DEL", a hotel name. Null if unparsed.
  final String? route;

  /// Booking reference / PNR.
  final String? code;

  /// Departure or check-in moment; null when the email carried no date.
  final DateTime? departure;

  final DateTime lastSeen;
  final String sourceEmailId;
  final String? manageUrl;

  /// True when check-in is open *now* or a boarding pass is ready — the trip's
  /// action has become time-critical, distinct from a distant confirmed flight.
  final bool boardingReady;

  const TravelItem({
    required this.kind,
    required this.provider,
    this.route,
    this.code,
    this.departure,
    required this.lastSeen,
    required this.sourceEmailId,
    this.manageUrl,
    this.boardingReady = false,
  });

  /// Past trips fall off after a fortnight.
  bool get isStale =>
      (departure ?? lastSeen)
          .isBefore(DateTime.now().subtract(const Duration(days: 14)));

  String get dedupeKey => code != null && code!.isNotEmpty
      ? '${provider.toLowerCase()}|${code!.toLowerCase()}'
      : '${provider.toLowerCase()}|${route?.toLowerCase() ?? ''}|'
          '${departure?.toIso8601String() ?? lastSeen.toIso8601String().substring(0, 10)}';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'provider': provider,
        'route': route,
        'code': code,
        'departure': departure?.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'manageUrl': manageUrl,
        'boardingReady': boardingReady,
      };

  factory TravelItem.fromJson(Map<String, dynamic> json) => TravelItem(
        kind: TravelKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => TravelKind.flight,
        ),
        provider: json['provider'] as String,
        route: json['route'] as String?,
        code: json['code'] as String?,
        departure: json['departure'] == null
            ? null
            : DateTime.parse(json['departure'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        manageUrl: json['manageUrl'] as String?,
        boardingReady: json['boardingReady'] as bool? ?? false,
      );
}

/// Something the user should look at that isn't money or a package —
/// produced by the AI pass over emails the rule extractors didn't claim.
class AttentionItem {
  final String title;
  final String reason;
  final DateTime date;
  final String sourceEmailId;

  /// Most relevant link from the email (verify page, document, etc.).
  final String? linkUrl;

  const AttentionItem({
    required this.title,
    required this.reason,
    required this.date,
    required this.sourceEmailId,
    this.linkUrl,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'reason': reason,
        'date': date.toIso8601String(),
        'sourceEmailId': sourceEmailId,
        'linkUrl': linkUrl,
      };

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
        title: json['title'] as String,
        reason: json['reason'] as String,
        date: DateTime.parse(json['date'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
        linkUrl: json['linkUrl'] as String?,
      );
}

class DailyBrief {
  final String headline;
  final List<String> bullets;
  final DateTime generatedAt;

  const DailyBrief({
    required this.headline,
    required this.bullets,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'bullets': bullets,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory DailyBrief.fromJson(Map<String, dynamic> json) => DailyBrief(
        headline: json['headline'] as String,
        bullets: (json['bullets'] as List).cast<String>(),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
      );
}

/// The full extracted state of the account — what the app persists and renders.
/// A subscription's price moved between syncs. The raise nobody announces
/// loudly — buried in a renewal receipt — is exactly the thing a paying user
/// wants surfaced. Detected by comparing the previous snapshot's amount to
/// the fresh scan's; persisted so the alert survives until it goes stale.
class PriceChange {
  final String service;
  final double oldAmount;
  final double newAmount;
  final String currency;
  final Cadence cadence;
  final DateTime detectedAt;
  final String sourceEmailId;

  const PriceChange({
    required this.service,
    required this.oldAmount,
    required this.newAmount,
    required this.currency,
    required this.cadence,
    required this.detectedAt,
    required this.sourceEmailId,
  });

  bool get isIncrease => newAmount > oldAmount;

  /// Monthly delta, signed — yearly plans normalized so the "₹/mo" framing
  /// stays honest.
  double get monthlyDelta => cadence == Cadence.yearly
      ? (newAmount - oldAmount) / 12.0
      : (newAmount - oldAmount);

  /// A change stays interesting for a quarter — long enough to act on the
  /// renewal it affects, short enough not to haunt the feed forever.
  bool get isStale =>
      detectedAt.isBefore(DateTime.now().subtract(const Duration(days: 90)));

  String get dedupeKey =>
      '${service.toLowerCase()}|${newAmount.toStringAsFixed(2)}';

  /// Adopts the AI audit's better brand name, same as [Subscription.withService]
  /// — a change on "NETFLIX.COM BILLING" should read "Netflix" too.
  PriceChange withService(String name) => PriceChange(
        service: name,
        oldAmount: oldAmount,
        newAmount: newAmount,
        currency: currency,
        cadence: cadence,
        detectedAt: detectedAt,
        sourceEmailId: sourceEmailId,
      );

  Map<String, dynamic> toJson() => {
        'service': service,
        'oldAmount': oldAmount,
        'newAmount': newAmount,
        'currency': currency,
        'cadence': cadence.name,
        'detectedAt': detectedAt.toIso8601String(),
        'sourceEmailId': sourceEmailId,
      };

  factory PriceChange.fromJson(Map<String, dynamic> json) => PriceChange(
        service: json['service'] as String,
        oldAmount: (json['oldAmount'] as num).toDouble(),
        newAmount: (json['newAmount'] as num).toDouble(),
        currency: json['currency'] as String,
        cadence: Cadence.values.firstWhere(
          (c) => c.name == json['cadence'],
          orElse: () => Cadence.monthly,
        ),
        detectedAt: DateTime.parse(json['detectedAt'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
      );
}

/// Something NoMail taught itself to recognise, that is none of the shapes it
/// was born knowing.
///
/// The playbook can learn to recognise any recurring document, but until this
/// existed the app had no way to *represent* one: a learned type that was not a
/// bill, delivery, subscription or meeting collapsed into an [AttentionItem],
/// which meant a school fee circular arrived with no amount, no deadline (the
/// email's own date stood in for one), and the weight and domain of a security
/// alert. The app could learn a new use-case and then describe it uselessly.
///
/// So this is deliberately shaped like "a thing with a name, maybe some money,
/// maybe a date, and a link" — the least the app can know about a document and
/// still be helpful. [typeId] points back at the recipe that produced it, so
/// Settings → Knowledge can explain where the card came from and switch it off.
class LearnedItem {
  /// The learned type's human label, e.g. 'Society maintenance'.
  final String label;

  /// Slug of the [ContentType] that recognised this — the audit trail.
  final String typeId;

  /// One line of detail, usually the subject or the recipe's own subtitle.
  final String summary;

  /// Money the recipe found, when it found any.
  final double? amount;
  final String currency;

  /// When this actually matters — a due date, an appointment, a deadline. Null
  /// when the recipe extracted no date, and deliberately *not* defaulted to the
  /// email's arrival: a wrong deadline is worse than no deadline.
  final DateTime? deadline;

  /// The best action URL the recipe built, if any.
  final String? url;

  final DateTime lastSeen;
  final String sourceEmailId;

  const LearnedItem({
    required this.label,
    required this.typeId,
    required this.summary,
    this.amount,
    this.currency = 'INR',
    this.deadline,
    this.url,
    required this.lastSeen,
    required this.sourceEmailId,
  });

  /// Past its deadline, when it had one.
  bool get isOverdue =>
      deadline != null && deadline!.isBefore(DateTime.now());

  /// Learned items age out faster than bills: the app is less sure what they
  /// are, so it should be less insistent about keeping them around. A dated
  /// item survives until a week past its date; an undated one for 30 days.
  bool get isStale {
    final now = DateTime.now();
    final date = deadline;
    if (date != null) return date.isBefore(now.subtract(const Duration(days: 7)));
    return lastSeen.isBefore(now.subtract(const Duration(days: 30)));
  }

  /// One per recipe per source email: the same circular re-read must not
  /// produce two cards, but two genuine notices from one recipe must.
  String get dedupeKey => '$typeId|$sourceEmailId';

  LearnedItem withLabel(String name) => LearnedItem(
        label: name,
        typeId: typeId,
        summary: summary,
        amount: amount,
        currency: currency,
        deadline: deadline,
        url: url,
        lastSeen: lastSeen,
        sourceEmailId: sourceEmailId,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'typeId': typeId,
        'summary': summary,
        'amount': amount,
        'currency': currency,
        'deadline': deadline?.toIso8601String(),
        'url': url,
        'lastSeen': lastSeen.toIso8601String(),
        'sourceEmailId': sourceEmailId,
      };

  factory LearnedItem.fromJson(Map<String, dynamic> json) => LearnedItem(
        label: json['label'] as String,
        typeId: json['typeId'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'INR',
        deadline: json['deadline'] == null
            ? null
            : DateTime.tryParse(json['deadline'] as String),
        url: json['url'] as String?,
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        sourceEmailId: json['sourceEmailId'] as String,
      );
}

class InsightSnapshot {
  final List<Subscription> subscriptions;
  final List<Bill> bills;
  final List<Delivery> deliveries;
  final List<EventItem> events;
  final List<FeedItem> feed;
  final List<TravelItem> travel;
  final List<PaymentAlert> payments;
  final List<ReturnItem> returns;
  final List<PriceChange> priceChanges;

  /// Insights from recipes the app wrote for itself — see [LearnedItem].
  final List<LearnedItem> learned;
  final List<AttentionItem> attention;
  final DailyBrief? brief;
  final DateTime? lastSyncedAt;
  final int emailsScanned;

  const InsightSnapshot({
    this.subscriptions = const [],
    this.bills = const [],
    this.deliveries = const [],
    this.events = const [],
    this.feed = const [],
    this.travel = const [],
    this.payments = const [],
    this.returns = const [],
    this.priceChanges = const [],
    this.learned = const [],
    this.attention = const [],
    this.brief,
    this.lastSyncedAt,
    this.emailsScanned = 0,
  });

  bool get isEmpty =>
      subscriptions.isEmpty &&
      bills.isEmpty &&
      deliveries.isEmpty &&
      events.isEmpty &&
      feed.isEmpty &&
      travel.isEmpty &&
      payments.isEmpty &&
      returns.isEmpty &&
      learned.isEmpty &&
      attention.isEmpty;

  /// Content from the last two weeks, newest first — the reading queue.
  List<FeedItem> get recentFeed =>
      feed.where((f) => f.date.isAfter(
              DateTime.now().subtract(const Duration(days: 21)))).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double get monthlyRecurring =>
      subscriptions.fold(0.0, (sum, s) => sum + s.monthlyAmount);

  /// Monthly recurring totals grouped by currency — mixing currencies into
  /// one number would be a lie.
  Map<String, double> get recurringByCurrency {
    final totals = <String, double>{};
    for (final sub in subscriptions) {
      totals[sub.currency] = (totals[sub.currency] ?? 0) + sub.monthlyAmount;
    }
    return totals;
  }

  /// The currency carrying the largest share of recurring spend.
  String get dominantCurrency {
    final totals = recurringByCurrency;
    if (totals.isEmpty) return 'INR';
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<Bill> get unpaidUpcoming =>
      bills.where((b) => b.dueDate != null && !b.isStale).toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

  List<Delivery> get activeDeliveries =>
      deliveries.where((d) => d.isActive).toList();

  List<TravelItem> get upcomingTravel =>
      travel.where((t) => !t.isStale).toList()
        ..sort((a, b) => (a.departure ?? a.lastSeen)
            .compareTo(b.departure ?? b.lastSeen));

  List<PaymentAlert> get activePayments =>
      payments.where((p) => !p.isStale).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Price changes still worth showing, biggest monthly impact first.
  List<PriceChange> get activePriceChanges =>
      priceChanges.where((c) => !c.isStale).toList()
        ..sort((a, b) =>
            b.monthlyDelta.abs().compareTo(a.monthlyDelta.abs()));

  /// Learned items still worth showing: overdue and dated first, then the
  /// undated ones by how recently they arrived.
  List<LearnedItem> get activeLearned =>
      learned.where((l) => !l.isStale).toList()
        ..sort((a, b) {
          final ad = a.deadline, bd = b.deadline;
          if (ad != null && bd != null) return ad.compareTo(bd);
          if (ad != null) return -1;
          if (bd != null) return 1;
          return b.lastSeen.compareTo(a.lastSeen);
        });

  List<ReturnItem> get openReturns =>
      returns.where((r) => !r.isStale).toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));

  /// Upcoming (non-cancelled, future) events, soonest first.
  List<EventItem> get upcomingEvents =>
      events.where((e) => e.isUpcoming).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<EventItem> get todayEvents =>
      upcomingEvents.where((e) => e.isToday).toList();

  InsightSnapshot copyWith({
    List<Subscription>? subscriptions,
    List<Bill>? bills,
    List<Delivery>? deliveries,
    List<EventItem>? events,
    List<FeedItem>? feed,
    List<TravelItem>? travel,
    List<PaymentAlert>? payments,
    List<ReturnItem>? returns,
    List<PriceChange>? priceChanges,
    List<LearnedItem>? learned,
    List<AttentionItem>? attention,
    DailyBrief? brief,
    DateTime? lastSyncedAt,
    int? emailsScanned,
  }) =>
      InsightSnapshot(
        subscriptions: subscriptions ?? this.subscriptions,
        bills: bills ?? this.bills,
        deliveries: deliveries ?? this.deliveries,
        events: events ?? this.events,
        feed: feed ?? this.feed,
        travel: travel ?? this.travel,
        payments: payments ?? this.payments,
        returns: returns ?? this.returns,
        priceChanges: priceChanges ?? this.priceChanges,
        learned: learned ?? this.learned,
        attention: attention ?? this.attention,
        brief: brief ?? this.brief,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        emailsScanned: emailsScanned ?? this.emailsScanned,
      );

  Map<String, dynamic> toJson() => {
        'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
        'bills': bills.map((b) => b.toJson()).toList(),
        'deliveries': deliveries.map((d) => d.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'feed': feed.map((f) => f.toJson()).toList(),
        'travel': travel.map((t) => t.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'returns': returns.map((r) => r.toJson()).toList(),
        'priceChanges': priceChanges.map((c) => c.toJson()).toList(),
        'learned': learned.map((l) => l.toJson()).toList(),
        'attention': attention.map((a) => a.toJson()).toList(),
        'brief': brief?.toJson(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'emailsScanned': emailsScanned,
      };

  factory InsightSnapshot.fromJson(Map<String, dynamic> json) =>
      InsightSnapshot(
        subscriptions: ((json['subscriptions'] ?? []) as List)
            .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
            .toList(),
        bills: ((json['bills'] ?? []) as List)
            .map((e) => Bill.fromJson(e as Map<String, dynamic>))
            .toList(),
        deliveries: ((json['deliveries'] ?? []) as List)
            .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: ((json['events'] ?? []) as List)
            .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        feed: ((json['feed'] ?? []) as List)
            .map((e) => FeedItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        travel: ((json['travel'] ?? []) as List)
            .map((e) => TravelItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: ((json['payments'] ?? []) as List)
            .map((e) => PaymentAlert.fromJson(e as Map<String, dynamic>))
            .toList(),
        returns: ((json['returns'] ?? []) as List)
            .map((e) => ReturnItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        learned: ((json['learned'] ?? []) as List)
            .map((e) => LearnedItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        priceChanges: ((json['priceChanges'] ?? []) as List)
            .map((e) => PriceChange.fromJson(e as Map<String, dynamic>))
            .toList(),
        attention: ((json['attention'] ?? []) as List)
            .map((e) => AttentionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        brief: json['brief'] == null
            ? null
            : DailyBrief.fromJson(json['brief'] as Map<String, dynamic>),
        lastSyncedAt: json['lastSyncedAt'] == null
            ? null
            : DateTime.parse(json['lastSyncedAt'] as String),
        emailsScanned: (json['emailsScanned'] ?? 0) as int,
      );
}
