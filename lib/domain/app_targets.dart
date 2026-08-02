/// The app catalog — which native apps NoMail knows how to reach.
///
/// WHY THIS EXISTS
/// NoMail's promise is "one tap lands you where the money/parcel/meeting
/// actually is". On iOS that means: open the *native app* when the user has
/// it, and otherwise keep them inside NoMail in a WebView. This file is the
/// knowledge half of that decision; `core/installed_apps.dart` is the
/// platform half.
///
/// THE THREE iOS FACTS THAT SHAPE THIS FILE
/// 1. `canLaunchUrl` on a custom scheme (`delhivery://`) returns false unless
///    that scheme is listed in `LSApplicationQueriesSchemes`. The declaration
///    list IS the detection capability — every non-null [AppTarget.probeScheme]
///    here must also appear in `ios/Runner/Info.plist`.
/// 2. iOS caps `LSApplicationQueriesSchemes` at 50 entries. The catalog stays
///    under that ceiling on purpose; adding a target with a scheme spends
///    budget, so prefer `probeScheme: null` for apps we only ever reach by
///    universal link.
/// 3. `canLaunchUrl` on an https URL is useless for detection — it returns
///    true always, because Safari can open it. There is no iOS API to ask
///    "does the Delhivery app claim delhivery.com?".
///
/// CONSEQUENCE — the probe/launch split
/// We *probe* with the custom scheme but *launch* the https universal link.
/// A scheme probe is reliable even when the scheme's launch URL format is
/// undocumented, whereas a guessed `app://some/path` usually fails silently
/// and strands the user. [universalHosts] is what makes the launch side work:
/// it maps an https URL back to the app that probably claims it.
/// [launchFormatVerified] is true only where an official doc pins down a
/// scheme URL we could construct ourselves — that flag is a licence to build
/// a scheme URL, nothing else.
///
/// Pure Dart: no Flutter, no plugins, fully unit testable.
library;

enum AppCategory {
  courier,
  merchant,
  payment,
  travel,
  meeting,
  maps,
  finance,
  other,
}

/// One native app NoMail may hand off to.
class AppTarget {
  /// Stable identifier used in code, caches and tests ('delhivery').
  final String key;

  /// Human label for the UI ('Delhivery').
  final String name;

  /// Bare custom scheme for *detection* — no `://`, no colon. Null when the
  /// app has no known scheme (universal-link-only apps like Google Meet):
  /// those cost no Info.plist budget and are simply never detected.
  final String? probeScheme;

  /// Hosts this app claims as universal links. Used by [AppCatalog.forHost] to
  /// decide "this https URL probably belongs to that app". Longest suffix
  /// wins, so listing the bare domain also covers its subdomains.
  final List<String> universalHosts;

  /// True ONLY when an official doc specifies a scheme URL format we can
  /// construct (e.g. `uber://riderequest?...`). False means: probe the scheme
  /// to detect, but launch the https link — never invent a scheme path.
  final bool launchFormatVerified;

  final AppCategory category;

  const AppTarget({
    required this.key,
    required this.name,
    required this.probeScheme,
    this.universalHosts = const [],
    this.launchFormatVerified = false,
    required this.category,
  });

  /// The URI to hand `canLaunchUrl` for detection — `scheme://`, nothing more.
  /// Null for universal-link-only apps.
  Uri? get probeUri =>
      probeScheme == null ? null : Uri(scheme: probeScheme, host: '');

  @override
  String toString() => 'AppTarget($key)';
}

/// Every app NoMail knows about, plus the lookups the action layer needs.
///
/// Sources are cited inline next to each entry whose launch format is
/// verified. Entries marked `// UNVERIFIED launch format — probe only` carry a
/// widely-reported scheme that is good enough for detection: a wrong guess is
/// a false negative, which just means NoMail keeps the user in its WebView.
class AppCatalog {
  const AppCatalog._();

  static const List<AppTarget> all = <AppTarget>[
    // ---------------------------------------------------------------- payment
    // Schemes for the UPI apps below are the ones Indian payment gateways
    // declare in their own iOS SDK setup docs (PhonePe developer docs,
    // Cashfree iOS SDK, Juspay blaze-sdk-ios), which is the closest thing to
    // an authoritative list. Payment *intents* should use the NPCI
    // `upi://pay?pa=…&pn=…&am=…&cu=INR` spec (UPI Linking Specification 1.7)
    // rather than any single app's scheme — that's the launcher's business,
    // not this catalog's.
    AppTarget(
      key: 'google_pay',
      name: 'Google Pay',
      probeScheme: 'gpay',
      universalHosts: ['pay.google.com'],
      // VERIFIED: `gpay://upi/pay?pa=…&pn=…&am=…&cu=INR&tr=…`
      // https://developers.google.com/pay/india/api/android/in-app-payments
      launchFormatVerified: true,
      category: AppCategory.payment,
    ),
    AppTarget(
      key: 'phonepe',
      name: 'PhonePe',
      probeScheme: 'phonepe',
      universalHosts: ['phonepe.com'],
      // UNVERIFIED launch format — probe only. Scheme per
      // https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/ios/sdk-setup
      category: AppCategory.payment,
    ),
    AppTarget(
      key: 'paytm',
      name: 'Paytm',
      probeScheme: 'paytmmp',
      universalHosts: ['paytm.com', 'paytm.me'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.payment,
    ),
    AppTarget(
      key: 'bhim',
      name: 'BHIM',
      probeScheme: 'bhim',
      universalHosts: ['bhimupi.org.in'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.payment,
    ),
    AppTarget(
      key: 'cred',
      name: 'CRED',
      probeScheme: 'credpay',
      universalHosts: ['cred.club'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.payment,
    ),
    AppTarget(
      key: 'amazon_pay',
      name: 'Amazon Pay',
      probeScheme: 'amazonpay',
      // No universalHosts on purpose: amazon.in belongs to the shopping app.
      // UNVERIFIED launch format — probe only.
      category: AppCategory.payment,
    ),

    // ---------------------------------------------------------------- courier
    // Indian couriers publish no deep-link docs at all. Every scheme here is
    // the reported/bundle-name form and is used for detection only; tracking
    // always launches the https tracking page (see domain/actions.dart).
    AppTarget(
      key: 'delhivery',
      name: 'Delhivery',
      probeScheme: 'delhivery',
      universalHosts: ['delhivery.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'bluedart',
      name: 'Blue Dart',
      probeScheme: 'bluedart',
      universalHosts: ['bluedart.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'dtdc',
      name: 'DTDC',
      probeScheme: 'dtdc',
      universalHosts: ['dtdc.in', 'dtdc.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'ekart',
      name: 'Ekart',
      probeScheme: 'ekart',
      universalHosts: ['ekartlogistics.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'xpressbees',
      name: 'XpressBees',
      probeScheme: 'xpressbees',
      universalHosts: ['xpressbees.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'ecom_express',
      name: 'Ecom Express',
      probeScheme: 'ecomexpress',
      universalHosts: ['ecomexpress.in'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'india_post',
      name: 'India Post',
      probeScheme: 'indiapost',
      universalHosts: ['indiapost.gov.in'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'shadowfax',
      name: 'Shadowfax',
      probeScheme: 'shadowfax',
      universalHosts: ['shadowfax.in'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'shiprocket',
      name: 'Shiprocket',
      probeScheme: 'shiprocket',
      universalHosts: ['shiprocket.in', 'shiprocket.co'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'fedex',
      name: 'FedEx',
      probeScheme: 'fedex',
      universalHosts: ['fedex.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'dhl',
      name: 'DHL',
      probeScheme: 'dhl',
      universalHosts: ['dhl.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),
    AppTarget(
      key: 'ups',
      name: 'UPS',
      probeScheme: 'ups',
      universalHosts: ['ups.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.courier,
    ),

    // --------------------------------------------------------------- merchant
    AppTarget(
      key: 'amazon',
      name: 'Amazon',
      // Amazon's iOS app registers the reverse-DNS shopping schemes; this is
      // the widely reported one. Dots are legal in a URL scheme (RFC 3986).
      probeScheme: 'com.amazon.mobile.shopping',
      universalHosts: ['amazon.in', 'amazon.com', 'amzn.to'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'flipkart',
      name: 'Flipkart',
      probeScheme: 'flipkart',
      universalHosts: ['flipkart.com', 'fkrt.it'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'myntra',
      name: 'Myntra',
      probeScheme: 'myntra',
      universalHosts: ['myntra.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'ajio',
      name: 'AJIO',
      probeScheme: 'ajio',
      universalHosts: ['ajio.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'meesho',
      name: 'Meesho',
      probeScheme: 'meesho',
      universalHosts: ['meesho.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'nykaa',
      name: 'Nykaa',
      probeScheme: 'nykaa',
      universalHosts: ['nykaa.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'zepto',
      name: 'Zepto',
      probeScheme: 'zepto',
      universalHosts: ['zeptonow.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'blinkit',
      name: 'Blinkit',
      probeScheme: 'blinkit',
      universalHosts: ['blinkit.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'swiggy',
      name: 'Swiggy',
      probeScheme: 'swiggy',
      universalHosts: ['swiggy.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'zomato',
      name: 'Zomato',
      probeScheme: 'zomato',
      universalHosts: ['zomato.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'jiomart',
      name: 'JioMart',
      probeScheme: 'jiomart',
      universalHosts: ['jiomart.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'tata_cliq',
      name: 'Tata CLiQ',
      probeScheme: 'tatacliq',
      universalHosts: ['tatacliq.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),
    AppTarget(
      key: 'bigbasket',
      name: 'BigBasket',
      probeScheme: 'bigbasket',
      universalHosts: ['bigbasket.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.merchant,
    ),

    // ----------------------------------------------------------------- travel
    AppTarget(
      key: 'makemytrip',
      name: 'MakeMyTrip',
      probeScheme: 'makemytrip',
      universalHosts: ['makemytrip.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.travel,
    ),
    AppTarget(
      key: 'cleartrip',
      name: 'Cleartrip',
      probeScheme: 'cleartrip',
      universalHosts: ['cleartrip.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.travel,
    ),
    AppTarget(
      key: 'ixigo',
      name: 'ixigo',
      probeScheme: 'ixigo',
      universalHosts: ['ixigo.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.travel,
    ),
    AppTarget(
      key: 'irctc',
      name: 'IRCTC',
      probeScheme: 'irctc',
      universalHosts: ['irctc.co.in', 'irctc.com'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.travel,
    ),
    AppTarget(
      key: 'indigo',
      name: 'IndiGo',
      probeScheme: 'goindigo',
      universalHosts: ['goindigo.in'],
      // UNVERIFIED launch format — probe only.
      category: AppCategory.travel,
    ),

    // ---------------------------------------------------------------- meeting
    AppTarget(
      key: 'zoom',
      name: 'Zoom',
      probeScheme: 'zoomus',
      universalHosts: ['zoom.us'],
      // VERIFIED: `zoomus://` is the documented scheme for launching the Zoom
      // client from another iOS app. Joining a specific meeting still goes
      // through the https invite link.
      // https://developers.zoom.us/docs/meeting-sdk/ios/resource/launch-zoom-client-from-your-app/
      launchFormatVerified: true,
      category: AppCategory.meeting,
    ),
    AppTarget(
      key: 'teams',
      name: 'Microsoft Teams',
      probeScheme: 'msteams',
      universalHosts: ['teams.microsoft.com', 'teams.live.com'],
      // UNVERIFIED launch format — probe only. Microsoft documents the
      // msteams:// protocol handler but explicitly tells you to ship
      // https://teams.microsoft.com/l/… instead, which is what we launch.
      // https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/build-and-test/deep-links
      category: AppCategory.meeting,
    ),
    AppTarget(
      key: 'webex',
      name: 'Webex',
      probeScheme: 'webex',
      universalHosts: ['webex.com'],
      // UNVERIFIED launch format — probe only. Cisco publishes webexteams://
      // and webexstart:// forms for other purposes, not meeting join.
      category: AppCategory.meeting,
    ),
    AppTarget(
      key: 'google_meet',
      name: 'Google Meet',
      // Universal-link only by design — no scheme, so no Info.plist budget
      // spent and no detection. Meet links always open via meet.google.com,
      // which the app claims when installed.
      probeScheme: null,
      universalHosts: ['meet.google.com'],
      category: AppCategory.meeting,
    ),

    // ------------------------------------------------------------------- maps
    AppTarget(
      key: 'google_maps',
      name: 'Google Maps',
      probeScheme: 'comgooglemaps',
      universalHosts: ['maps.google.com', 'maps.app.goo.gl'],
      // VERIFIED: `comgooglemaps://?q=…&center=…&zoom=…` — Google's own iOS
      // URL scheme reference, which also tells you to declare the scheme in
      // LSApplicationQueriesSchemes and canOpenURL-check before launching.
      // https://developers.google.com/maps/documentation/urls/ios-urlscheme
      launchFormatVerified: true,
      category: AppCategory.maps,
    ),

    // ------------------------------------------------------------------ other
    AppTarget(
      key: 'uber',
      name: 'Uber',
      probeScheme: 'uber',
      universalHosts: ['uber.com'],
      // VERIFIED: `uber://riderequest?pickup[latitude]=…&dropoff[…]=…`
      // (the older documented form is `uber://?action=setPickup&…`).
      // https://developer.uber.com/docs/deep-linking
      launchFormatVerified: true,
      category: AppCategory.other,
    ),
    AppTarget(
      key: 'ola',
      name: 'Ola',
      probeScheme: 'olacabs',
      universalHosts: ['olacabs.com'],
      // VERIFIED: `olacabs://app/launch?…` is Ola's documented app deep link
      // (falls back to the store when the app is absent).
      // https://developers.olacabs.com/docs/deep-linking
      launchFormatVerified: true,
      category: AppCategory.other,
    ),
    AppTarget(
      key: 'whatsapp',
      name: 'WhatsApp',
      probeScheme: 'whatsapp',
      universalHosts: ['wa.me', 'api.whatsapp.com', 'chat.whatsapp.com'],
      // UNVERIFIED launch format — probe only. WhatsApp's official
      // click-to-chat link is https://wa.me/<number>; the whatsapp://send
      // form is widely used but not what WhatsApp documents, so we probe the
      // scheme and launch wa.me.
      category: AppCategory.other,
    ),
  ];

  /// Every declared probe scheme — exactly what must be in
  /// `LSApplicationQueriesSchemes`. iOS caps that array at 50 entries.
  static const int iosSchemeLimit = 50;

  static List<String> get probeSchemes => all
      .map((t) => t.probeScheme)
      .whereType<String>()
      .toList(growable: false);

  static AppTarget? byKey(String key) {
    for (final target in all) {
      if (target.key == key) return target;
    }
    return null;
  }

  /// The app that most likely claims [host] as a universal link.
  ///
  /// Longest-suffix match, so `sub.delhivery.com` resolves to Delhivery via
  /// the registered `delhivery.com`, while an exactly-listed host
  /// (`teams.microsoft.com`) beats a shorter one from another target.
  static AppTarget? forHost(String host) {
    var candidate = host.trim().toLowerCase();
    while (candidate.endsWith('.')) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    if (candidate.isEmpty) return null;

    AppTarget? best;
    var bestLength = -1;
    for (final target in all) {
      for (final registered in target.universalHosts) {
        final match = candidate == registered ||
            candidate.endsWith('.$registered');
        if (match && registered.length > bestLength) {
          best = target;
          bestLength = registered.length;
        }
      }
    }
    return best;
  }

  /// Convenience: the app that claims [uri]'s host, or null for non-web URIs.
  static AppTarget? forUri(Uri uri) =>
      uri.host.isEmpty ? null : forHost(uri.host);

  static List<AppTarget> get paymentApps => byCategory(AppCategory.payment);

  static List<AppTarget> get courierApps => byCategory(AppCategory.courier);

  static List<AppTarget> byCategory(AppCategory category) =>
      all.where((t) => t.category == category).toList(growable: false);
}
