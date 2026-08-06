/// Decides *how* a link should open: the native app, an in-app WebView, or
/// handed to iOS.
///
/// Two iOS facts drive the whole design.
///
/// First, there is no way to ask whether an installed app claims a given
/// https URL — `canLaunchUrl` on https always says yes, because Safari can
/// open it. So detection runs on custom schemes ([InstalledApps]), while the
/// thing we actually launch stays the https universal link: iOS routes it to
/// the app when the app claims it, and almost no Indian courier or merchant
/// documents a scheme URL format we could construct instead.
///
/// Second, a WKWebView has its own cookie jar. Anything behind a login —
/// Gmail, a bank, a subscription's billing page — renders logged-out inside
/// it, which looks exactly like a broken link. Those hosts are handed to iOS
/// instead, where Safari's session already exists. The WebView is for public
/// pages (tracking, order status), where keeping the user inside NoMail costs
/// them nothing and lets us ask whether the link was right.
library;

import '../core/host_routing.dart';
import '../core/installed_apps.dart';
import 'actions.dart';
import 'app_targets.dart';

enum LinkOpenMode {
  /// The destination app is installed; iOS will route the universal link.
  nativeApp,

  /// Public page, no app — keep the user inside NoMail.
  inAppWebView,

  /// Not ours to render: a non-http scheme, or a page that needs the
  /// system's logged-in browser.
  systemHandoff,

  /// The source message, rendered from a fresh fetch inside NoMail.
  ///
  /// The exception that proves the WebView rule above: this is the one page we
  /// can show behind a login, because we are not loading a page at all — the
  /// body arrives over the authenticated Gmail API and is handed to the
  /// WebView as a string. No navigation, so no cookie jar to be empty.
  ///
  /// It exists because "Open email" has no working hand-off on iOS at all:
  /// mail.google.com claims no universal link for the Gmail app, so the https
  /// URL reaches Safari — a different session, frequently signed out.
  emailReader,
}

class LinkPlan {
  final Uri uri;
  final LinkOpenMode mode;

  /// What the user should expect to see — "Delhivery", "Safari", "NoMail".
  final String destination;

  /// [AppTarget.key] when [mode] is [LinkOpenMode.nativeApp]; drives the icon.
  final String? appKey;

  const LinkPlan({
    required this.uri,
    required this.mode,
    required this.destination,
    this.appKey,
  });

  /// Short suffix for an action label: "Track package · Delhivery".
  String get opensIn => switch (mode) {
        LinkOpenMode.nativeApp => destination,
        LinkOpenMode.inAppWebView => 'in NoMail',
        LinkOpenMode.systemHandoff => destination,
        LinkOpenMode.emailReader => 'in NoMail',
      };
}

/// Hosts that only make sense while signed in. A WebView would show these
/// logged-out, so they go to the system browser (or their own app) instead.
const _authGatedHosts = [
  'mail.google.com',
  'calendar.google.com',
  'myaccount.google.com',
  'accounts.google.com',
  'apps.apple.com',
  'netflix.com',
  'spotify.com',
  'primevideo.com',
  'hotstar.com',
  'youtube.com',
  'adobe.com',
  'github.com',
  'claude.ai',
  'openai.com',
  'linkedin.com',
  'dropbox.com',
  'figma.com',
  'notion.so',
  'vercel.com',
  'railway.app',
  'canva.com',
  'audible.in',
  // Anything money-shaped: never render a payment or bank page in our own
  // WebView, both for trust and because they are all behind a login.
  'billdesk.com',
  'razorpay.com',
  'payu.in',
  'paytm.com',
  'phonepe.com',
  'onlinesbi.sbi',
  'hdfcbank.com',
  'icicibank.com',
  'axisbank.com',
];

/// Action kinds that must never be rendered inside NoMail, whatever their
/// host: payments, calendar writes, and anything that is really an app
/// hand-off rather than a page.
const _neverWebView = {
  ActionKind.pay,
  ActionKind.remind,
  ActionKind.calendar,
  ActionKind.join,
  ActionKind.openEmail,
};
// `manage` is deliberately absent: the big billing pages (Netflix, Spotify,
// Apple…) are already covered by _authGatedHosts, and blocking the whole
// kind meant an unknown service's manage page went to Safari too — losing
// both the in-app experience and the feedback we could have collected.

bool _isAuthGated(String host) {
  final lower = host.toLowerCase();
  return _authGatedHosts.any((gated) =>
      lower == gated || lower.endsWith('.$gated'));
}

/// Chooses how [action] should open, given the apps actually on the device.
///
/// [installed] is [InstalledApps.detect]'s result; pass an empty set when
/// detection hasn't run yet — the plan degrades to web, never to nothing.
///
/// [externalHosts] is the user-taught routing memory ([HostRouting]): hosts
/// whose links must be handed to iOS so universal links can reach an app the
/// probe registry doesn't know about (registry detection is capped at 50
/// schemes by iOS — memory is the layer that scales past it).
/// [canReadEmail] is [MessageReader.isAvailable] — whether a signed-in backend
/// exists to fetch a message body with. It is a parameter rather than a lookup
/// so this file stays pure and the branch stays testable both ways.
LinkPlan planFor(
  InsightAction action,
  Set<String> installed, {
  Set<String> externalHosts = const {},
  bool canReadEmail = false,
}) {
  final uri = action.uri;

  // "Open email" reads the message here, ahead of every other rule including
  // the installed-app one.
  //
  // Not a preference for our own UI: it is the only branch that reliably ends
  // with the user looking at their email. Safari is a different session and
  // often signed out; the Gmail app has no documented message URL, so that
  // hand-off is a guess that fails silently when wrong. The reader always
  // works, needs no session, and keeps Gmail one tap away in its nav bar — so
  // nothing is lost by preferring it, and the tap now does the same thing on
  // every device instead of depending on what happens to be installed.
  if (action.kind == ActionKind.openEmail &&
      canReadEmail &&
      action.sourceEmailId != null) {
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.emailReader,
      destination: 'in NoMail',
    );
  }

  // Non-http schemes (upi:, tel:, mailto:) can only be resolved by iOS.
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    final target = AppCatalog.all
        .where((t) => t.probeScheme == uri.scheme)
        .firstOrNull;
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.systemHandoff,
      destination: target?.name ?? _schemeLabel(uri.scheme),
      appKey: target?.key,
    );
  }

  // The app that claims this host, if the user has it. Launch the https URL
  // regardless — iOS routes it, and it is the format we can trust.
  //
  // Never a constructed scheme URL. Gmail is why that rule is written down: a
  // widely-repeated `googlegmail:///cv=…` form was tried on a device and Gmail
  // answered "unable to understand link", after iOS had already reported the
  // launch as a success. A guessed scheme path cannot be made safe with a
  // fallback, because there is no failure to fall back from.
  final target = AppCatalog.forHost(uri.host);
  if (target != null && installed.contains(target.key)) {
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.nativeApp,
      destination: target.name,
      appKey: target.key,
    );
  }

  // The user taught us this site opens outside NoMail (usually because they
  // have its app and universal links only fire on an external launch).
  if (HostRouting.matches(uri.host, externalHosts)) {
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.systemHandoff,
      destination: target?.name ?? HostRouting.normalize(uri.host),
      appKey: target?.key,
    );
  }

  if (_neverWebView.contains(action.kind) || _isAuthGated(uri.host)) {
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.systemHandoff,
      destination: target?.name ?? 'Safari',
      appKey: target?.key,
    );
  }

  return LinkPlan(
    uri: uri,
    mode: LinkOpenMode.inAppWebView,
    destination: target?.name ?? uri.host,
  );
}

String _schemeLabel(String scheme) => switch (scheme) {
      'upi' => 'your UPI app',
      'tel' => 'Phone',
      'mailto' => 'Mail',
      'sms' => 'Messages',
      _ => scheme,
    };
