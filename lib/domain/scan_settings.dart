/// User-facing scan configuration.
///
/// The Gmail queries used to be hardcoded; these settings parameterize them so
/// the cost of a scan (emails fetched, history depth, AI calls) is the user's
/// choice rather than ours. Defaults reproduce the original hardcoded behavior
/// exactly, so an upgrade changes nothing until the user touches Settings.
library;

class ScanSettings {
  /// Gmail `maxResults` per query group.
  final int maxEmailsPerQuery;

  /// How far back the subscriptions/receipts query looks. Annual renewals are
  /// invisible below a year, which is why 365 is the floor we ship with.
  final int historyDays;

  /// Subscriptions + bills — two Gmail queries, one user-visible domain.
  final bool scanMoney;
  final bool scanDeliveries;
  final bool scanEvents;

  /// Newsletters, paid articles, YouTube uploads, podcast episodes.
  final bool scanReads;

  /// Flights, hotels, trains, bookings.
  final bool scanTravel;

  /// Sample recent mail that matches none of the targeted queries.
  ///
  /// This is what lets the app grow past the categories it was born knowing.
  /// Every other query above searches for words we already thought of, so the
  /// learner could only ever meet variations of shapes we had already named —
  /// a school fee circular or an insurance renewal was never fetched, so it
  /// could never be learned from. Discovery is the pass that shows the learner
  /// the actual inbox.
  ///
  /// It costs Gmail requests, not model tokens: the learner's own per-sync cap
  /// bounds spend regardless of how much mail reaches it.
  final bool scanDiscovery;

  /// Master switch for the cloud AI pass. Off means rules-only extraction —
  /// no email text ever leaves the device.
  final bool aiEnabled;
  final String aiModel;

  /// Hour of day (0-23, local) for the daily brief notification.
  final int briefHour;

  const ScanSettings({
    this.maxEmailsPerQuery = 25,
    this.historyDays = 365,
    this.scanMoney = true,
    this.scanDeliveries = true,
    this.scanEvents = true,
    this.scanReads = true,
    this.scanTravel = true,
    this.scanDiscovery = true,
    this.aiEnabled = true,
    this.aiModel = 'anthropic/claude-haiku-4.5',
    this.briefHour = 8,
  });

  static const emailCountOptions = <int>[25, 50, 100, 200];
  static const historyOptions = <int>[90, 180, 365, 730];

  /// Number of Gmail queries a scan will run. Money is two (receipts + bills),
  /// deliveries and events one each.
  int get _queryGroups =>
      (scanMoney ? 2 : 0) +
      (scanDeliveries ? 1 : 0) +
      (scanEvents ? 1 : 0) +
      (scanReads ? 1 : 0) +
      (scanTravel ? 1 : 0) +
      (scanDiscovery ? 1 : 0);

  /// Upper bound on emails fetched in one scan — the UI shows this as
  /// "up to N emails per scan". Real counts are lower after dedupe.
  int get estimatedMaxEmails => maxEmailsPerQuery * _queryGroups;

  /// One-line summary of what a scan will do, for the Settings header.
  String get describeScope {
    final domains = <String>[
      if (scanMoney) 'money',
      if (scanDeliveries) 'packages',
      if (scanEvents) 'meetings',
      if (scanReads) 'reads',
      if (scanTravel) 'trips',
      if (scanDiscovery) 'anything new',
    ];
    if (domains.isEmpty) return 'Nothing selected';

    final joined = domains.length == 1
        ? domains.first
        : '${domains.sublist(0, domains.length - 1).join(', ')} '
            'and ${domains.last}';
    final subject = joined[0].toUpperCase() + joined.substring(1);

    return '$subject · up to $estimatedMaxEmails emails · '
        '${_historyLabel(historyDays)} of history';
  }

  static String _historyLabel(int days) {
    if (days % 365 == 0) {
      final years = days ~/ 365;
      return years == 1 ? '1 year' : '$years years';
    }
    if (days % 30 == 0) {
      final months = days ~/ 30;
      return months == 1 ? '1 month' : '$months months';
    }
    return days == 1 ? '1 day' : '$days days';
  }

  ScanSettings copyWith({
    int? maxEmailsPerQuery,
    int? historyDays,
    bool? scanMoney,
    bool? scanDeliveries,
    bool? scanEvents,
    bool? scanReads,
    bool? scanTravel,
    bool? scanDiscovery,
    bool? aiEnabled,
    String? aiModel,
    int? briefHour,
  }) =>
      ScanSettings(
        maxEmailsPerQuery: maxEmailsPerQuery ?? this.maxEmailsPerQuery,
        historyDays: historyDays ?? this.historyDays,
        scanMoney: scanMoney ?? this.scanMoney,
        scanDeliveries: scanDeliveries ?? this.scanDeliveries,
        scanEvents: scanEvents ?? this.scanEvents,
        scanReads: scanReads ?? this.scanReads,
        scanTravel: scanTravel ?? this.scanTravel,
        scanDiscovery: scanDiscovery ?? this.scanDiscovery,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiModel: aiModel ?? this.aiModel,
        briefHour: briefHour ?? this.briefHour,
      );

  Map<String, dynamic> toJson() => {
        'maxEmailsPerQuery': maxEmailsPerQuery,
        'historyDays': historyDays,
        'scanMoney': scanMoney,
        'scanDeliveries': scanDeliveries,
        'scanEvents': scanEvents,
        'scanReads': scanReads,
        'scanTravel': scanTravel,
        'scanDiscovery': scanDiscovery,
        'aiEnabled': aiEnabled,
        'aiModel': aiModel,
        'briefHour': briefHour,
      };

  /// Every field falls back to its default: settings JSON written by an older
  /// build must keep loading after new fields are added.
  factory ScanSettings.fromJson(Map<String, dynamic> json) {
    const defaults = ScanSettings();
    int intOr(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    bool boolOr(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return ScanSettings(
      maxEmailsPerQuery:
          intOr('maxEmailsPerQuery', defaults.maxEmailsPerQuery),
      historyDays: intOr('historyDays', defaults.historyDays),
      scanMoney: boolOr('scanMoney', defaults.scanMoney),
      scanDeliveries: boolOr('scanDeliveries', defaults.scanDeliveries),
      scanEvents: boolOr('scanEvents', defaults.scanEvents),
      scanReads: boolOr('scanReads', defaults.scanReads),
      scanTravel: boolOr('scanTravel', defaults.scanTravel),
      scanDiscovery: boolOr('scanDiscovery', defaults.scanDiscovery),
      aiEnabled: boolOr('aiEnabled', defaults.aiEnabled),
      aiModel: json['aiModel'] is String
          ? json['aiModel'] as String
          : defaults.aiModel,
      briefHour: intOr('briefHour', defaults.briefHour),
    );
  }

  // Value equality: the sync engine compares old and new settings to decide
  // whether a re-scan is needed at all.
  @override
  bool operator ==(Object other) =>
      other is ScanSettings &&
      other.maxEmailsPerQuery == maxEmailsPerQuery &&
      other.historyDays == historyDays &&
      other.scanMoney == scanMoney &&
      other.scanDeliveries == scanDeliveries &&
      other.scanEvents == scanEvents &&
      other.scanReads == scanReads &&
      other.scanTravel == scanTravel &&
      other.aiEnabled == aiEnabled &&
      other.aiModel == aiModel &&
      other.briefHour == briefHour;

  @override
  int get hashCode => Object.hash(
        maxEmailsPerQuery,
        historyDays,
        scanMoney,
        scanDeliveries,
        scanEvents,
        scanReads,
        scanTravel,
        aiEnabled,
        aiModel,
        briefHour,
      );

  @override
  String toString() => 'ScanSettings(${toJson()})';
}
