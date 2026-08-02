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
LinkPlan planFor(InsightAction action, Set<String> installed) {
  final uri = action.uri;

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
  final target = AppCatalog.forHost(uri.host);
  if (target != null && installed.contains(target.key)) {
    return LinkPlan(
      uri: uri,
      mode: LinkOpenMode.nativeApp,
      destination: target.name,
      appKey: target.key,
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
