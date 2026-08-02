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

  const Subscription({
    required this.service,
    required this.amount,
    required this.currency,
    required this.cadence,
    this.nextRenewal,
    required this.lastSeen,
    required this.sourceEmailId,
    this.manageUrl,
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

  const Bill({
    required this.issuer,
    required this.amount,
    required this.currency,
    this.dueDate,
    required this.lastSeen,
    required this.sourceEmailId,
    this.payUrl,
  });

  Bill withIssuer(String name) => Bill(
        issuer: name,
        amount: amount,
        currency: currency,
        dueDate: dueDate,
        lastSeen: lastSeen,
        sourceEmailId: sourceEmailId,
        payUrl: payUrl,
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

  const Delivery({
    required this.merchant,
    this.carrier,
    required this.status,
    this.trackingNumber,
    this.eta,
    required this.lastSeen,
    required this.sourceEmailId,
    this.trackingUrl,
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

  const TravelItem({
    required this.kind,
    required this.provider,
    this.route,
    this.code,
    this.departure,
    required this.lastSeen,
    required this.sourceEmailId,
    this.manageUrl,
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
class InsightSnapshot {
  final List<Subscription> subscriptions;
  final List<Bill> bills;
  final List<Delivery> deliveries;
  final List<EventItem> events;
  final List<FeedItem> feed;
  final List<TravelItem> travel;
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
