/// Actions — every insight can be acted on, not just read.
///
/// Each builder returns the actions for one insight, best first:
/// a Delivery gets its exact tracking page, a Bill gets its pay link (or a
/// "remind me" calendar entry), an Event gets its join link and calendar day.
/// Every list ends with "Open email" — the source message is the one action
/// that always exists.
///
/// This layer is pure (no plugins, no platform code) so it's fully unit
/// testable; `core/action_launcher.dart` does the actual launching.
library;

import 'models.dart';

enum ActionKind { track, pay, remind, manage, join, calendar, openLink, openEmail }

class InsightAction {
  final String label;
  final Uri uri;
  final ActionKind kind;

  /// The message this action is *about*, prefix and all, when there is one.
  ///
  /// Set only by [openEmailAction]. Both URLs above destroy the id into a URL
  /// string, and the in-app reader needs it back to ask Gmail for the body —
  /// recovering it by taking the https URL apart again would make the reader
  /// depend on that URL's shape, which is exactly the coupling that let a
  /// false claim about universal links survive here for so long.
  final String? sourceEmailId;

  const InsightAction({
    required this.label,
    required this.uri,
    required this.kind,
    this.sourceEmailId,
  });
}

/// Deep link into the source message.
///
/// THERE IS NO WORKING HAND-OFF TO THE GMAIL iOS APP. Both mechanisms are
/// closed, each tested rather than assumed:
///
/// 1. Universal link — `mail.google.com` serves no `apple-app-site-association`
///    naming the Gmail app (verified 2026-08-05: Apple's CDN copy is
///    `www.google.com`'s, 48 entries, none of them Gmail). So the URL below
///    opens Safari on iOS however much it looks like an app link. Re-check with
///    `curl -s https://app-site-association.cdn-apple.com/a/v1/mail.google.com`
///    before believing otherwise.
/// 2. Custom scheme — `googlegmail:///cv=<id>/accountId=<N>&create-new-tab`,
///    the widely-repeated 2013 form, was shipped behind a fallback and tried on
///    a real device on 2026-08-06. **Gmail opened and rejected it**: "unable to
///    understand link". Removed. Note the failure mode before reaching for it
///    again — iOS reported the launch as *successful*, because the scheme was
///    registered and hand-off is all `UIApplication.open` reports. A fallback
///    on a false return therefore cannot catch a malformed path, and the user
///    sees Gmail's own error dialog. Anything reinstated here needs a format
///    verified on a device first, not a plausible one behind a safety net.
///
/// So this URL is the fallback, not the plan: `ui/screens/email_reader_screen`
/// renders the message in NoMail, and `domain/deep_links.dart` prefers it
/// whenever a signed-in backend exists to fetch a body with.
///
/// On Android the URL below does reach Gmail — `mail.google.com`'s
/// `assetlinks.json` delegates `handle_all_urls` to `com.google.android.gm`.
///
/// Multi-account email ids arrive prefixed `a<N>:<gmailId>` (see
/// MultiGmailSource). Gmail can't resolve the prefixed form, so the prefix is
/// stripped here — and repurposed: N is the account's index, which maps to
/// Gmail's `/mail/u/<N>/` authuser slot so the message opens in the *right*
/// inbox, not whichever account happens to be Gmail's default.
final _accountPrefixed = RegExp(r'^a(\d+):(.+)$');

/// Splits `a<N>:<gmailId>` into its parts, defaulting to account 0 for the
/// unprefixed ids demo fixtures and older snapshots carry.
({int account, String id}) splitSourceEmailId(String sourceEmailId) {
  final m = _accountPrefixed.firstMatch(sourceEmailId);
  return m == null
      ? (account: 0, id: sourceEmailId)
      : (account: int.parse(m.group(1)!), id: m.group(2)!);
}

/// Gmail's web URL for one conversation.
///
/// [id] must be a **thread** id wherever one is known. The fragment addresses
/// a conversation, not a message: for a single-message thread the two ids are
/// equal, which is why passing a message id looks fine on most transactional
/// mail — but on a reply chain they differ and Gmail cannot resolve it. The
/// callers that have refetched a message pass its `threadId`; the ones working
/// only from a stored insight pass what they have, because a probably-right
/// URL beats no action at all.
///
/// [accountEmail] is how a multi-account user lands in the right mailbox, and
/// it should be supplied wherever it is known. The [account] fallback is a
/// *positional* index into NoMail's own OAuth list, while Gmail's `/u/<N>/`
/// slot is the browser's own sign-in order — the two coincide only by luck, so
/// with several accounts connected the index form opens the wrong inbox.
///
/// The two selector forms were checked against Gmail rather than assumed
/// (2026-08-07): `/mail/u/<email>/` returns **404**, exactly like a bogus path,
/// so it is not a real form however often it is suggested. `?authuser=<email>`
/// is real — Gmail answers 301 and rewrites it to
/// `/mail/u/0/?authuser=<email>`, keeping the address. Browsers re-apply the
/// fragment across a redirect, so the conversation id survives that hop.
Uri gmailWebUrl({
  required int account,
  required String id,
  String? accountEmail,
}) =>
    Uri.parse(accountEmail != null && accountEmail.isNotEmpty
        ? 'https://mail.google.com/mail/'
            '?authuser=${Uri.encodeComponent(accountEmail)}#all/$id'
        : 'https://mail.google.com/mail/u/$account/#all/$id');

InsightAction openEmailAction(String sourceEmailId) {
  final parts = splitSourceEmailId(sourceEmailId);
  return InsightAction(
    label: 'Open email',
    // A stored insight only knows the message id — the thread id was never
    // captured at extraction time and is not worth a network call to learn,
    // because this URL is the fallback for when the reader cannot run. The
    // reader itself builds a thread-accurate URL from what it refetched.
    uri: gmailWebUrl(account: parts.account, id: parts.id),
    sourceEmailId: sourceEmailId,
    kind: ActionKind.openEmail,
  );
}

/// Carrier tracking page templates, keyed by the carrier names the
/// extractors produce. `{n}` is the tracking number slot.
const _carrierTrackTemplates = <String, String>{
  'Blue Dart': 'https://www.bluedart.com/trackdartresult?trackFor=0&trackNo={n}',
  'Delhivery': 'https://www.delhivery.com/track/package/{n}',
  'Ekart': 'https://ekartlogistics.com/shipmenttrack/{n}',
  'FedEx': 'https://www.fedex.com/fedextrack/?trknbr={n}',
  'UPS': 'https://www.ups.com/track?tracknum={n}',
  'DHL': 'https://www.dhl.com/in-en/home/tracking.html?tracking-id={n}',
  'USPS': 'https://tools.usps.com/go/TrackConfirmAction?tLabels={n}',
};

/// Universal multi-carrier tracker — the fallback when we have a tracking
/// number but no template for its carrier (DTDC, Shiprocket, India Post...).
String _universalTrackUrl(String trackingNumber) =>
    'https://t.17track.net/en#nums=${Uri.encodeComponent(trackingNumber)}';

List<InsightAction> actionsForDelivery(Delivery delivery) {
  final actions = <InsightAction>[];

  // The email's own tracking link beats any template — it lands on the
  // exact shipment, already authenticated for merchant pages.
  Uri? trackUri;
  if (delivery.trackingUrl != null) {
    trackUri = Uri.tryParse(delivery.trackingUrl!);
  }
  if (trackUri == null && delivery.trackingNumber != null) {
    final template = _carrierTrackTemplates[delivery.carrier];
    trackUri = Uri.parse(template != null
        ? template.replaceFirst(
            '{n}', Uri.encodeComponent(delivery.trackingNumber!))
        : _universalTrackUrl(delivery.trackingNumber!));
  }
  if (trackUri != null) {
    actions.add(InsightAction(
      label: 'Track package',
      uri: trackUri,
      kind: ActionKind.track,
    ));
  }

  actions.add(openEmailAction(delivery.sourceEmailId));
  return actions;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Google Calendar "create event" link — an all-day reminder on [date].
Uri _calendarReminderUri(String title, DateTime date) {
  final day = '${date.year}${_two(date.month)}${_two(date.day)}';
  final next = date.add(const Duration(days: 1));
  final dayAfter = '${next.year}${_two(next.month)}${_two(next.day)}';
  return Uri.parse(
      'https://calendar.google.com/calendar/render?action=TEMPLATE'
      '&text=${Uri.encodeComponent(title)}&dates=$day/$dayAfter');
}

List<InsightAction> actionsForBill(Bill bill) {
  final actions = <InsightAction>[];

  final payUri = bill.payUrl == null ? null : Uri.tryParse(bill.payUrl!);
  if (payUri != null) {
    actions.add(InsightAction(
      label: payUri.scheme == 'upi' ? 'Pay via UPI' : 'Pay now',
      uri: payUri,
      kind: ActionKind.pay,
    ));
  }
  if (bill.dueDate != null && !bill.isOverdue) {
    actions.add(InsightAction(
      label: 'Remind me',
      uri: _calendarReminderUri('Pay ${bill.issuer} bill', bill.dueDate!),
      kind: ActionKind.remind,
    ));
  }

  actions.add(openEmailAction(bill.sourceEmailId));
  return actions;
}

/// Account/billing pages, keyed by the service names the extractors produce.
const _manageUrls = <String, String>{
  'Netflix': 'https://www.netflix.com/account',
  'Spotify': 'https://www.spotify.com/account/subscription/',
  'YouTube Premium': 'https://www.youtube.com/paid_memberships',
  'Google': 'https://myaccount.google.com/subscriptions',
  'Apple': 'https://apps.apple.com/account/subscriptions',
  'iCloud': 'https://apps.apple.com/account/subscriptions',
  'Adobe': 'https://account.adobe.com/plans',
  'OpenAI': 'https://platform.openai.com/settings/organization/billing/overview',
  'Anthropic': 'https://claude.ai/settings/billing',
  'GitHub': 'https://github.com/settings/billing',
  'Notion': 'https://www.notion.so/settings',
  'Canva': 'https://www.canva.com/settings/billing-and-teams',
  'Disney+ Hotstar': 'https://www.hotstar.com/in/my-account',
  'Prime Video': 'https://www.primevideo.com/settings',
  'Audible': 'https://www.audible.in/account/account-details',
  'LinkedIn Premium': 'https://www.linkedin.com/premium/manage',
  'Dropbox': 'https://www.dropbox.com/account/plan',
  'Figma': 'https://www.figma.com/settings',
  'Vercel': 'https://vercel.com/account/billing',
  'Railway': 'https://railway.app/account',
};

List<InsightAction> actionsForSubscription(Subscription subscription) {
  final actions = <InsightAction>[];

  final manageUrl =
      subscription.manageUrl ?? _manageUrls[subscription.service];
  final manageUri = manageUrl == null ? null : Uri.tryParse(manageUrl);
  if (manageUri != null) {
    actions.add(InsightAction(
      label: 'Manage plan',
      uri: manageUri,
      kind: ActionKind.manage,
    ));
  }

  actions.add(openEmailAction(subscription.sourceEmailId));
  return actions;
}

/// Actions for a detected price change. The point of surfacing a hike is that
/// the user can act on it, and the only useful act is cancelling or downgrading
/// — so this leads with the manage link.
///
/// The change itself carries no URL (it is derived from two snapshots, not from
/// one email), so the link is borrowed from the live subscription of the same
/// name in [subscriptions]; the static registry is the fallback, and "Open
/// email" is the floor as everywhere else.
List<InsightAction> actionsForPriceChange(
  PriceChange change,
  List<Subscription> subscriptions,
) {
  final actions = <InsightAction>[];

  final key = change.service.toLowerCase();
  final live = subscriptions.where((s) => s.dedupeKey == key);
  final manageUrl = (live.isEmpty ? null : live.first.manageUrl) ??
      _manageUrls[change.service];
  final manageUri = manageUrl == null ? null : Uri.tryParse(manageUrl);
  if (manageUri != null) {
    actions.add(InsightAction(
      label: change.isIncrease ? 'Review plan' : 'Manage plan',
      uri: manageUri,
      kind: ActionKind.manage,
    ));
  }

  actions.add(openEmailAction(change.sourceEmailId));
  return actions;
}

/// Actions for a learned card.
///
/// The recipe already built whatever URL it knows — a payment page, a booking
/// lookup — and that URL is the whole reason the card is worth showing, so it
/// leads. A dated card also offers a calendar reminder, because the app cannot
/// promise to chase every learned deadline itself the way it does for bills.
/// "Open email" is the floor, as everywhere: the source message is the one
/// action that always works, and for a shape the app only half understands it is
/// the one the user is most likely to want.
List<InsightAction> actionsForLearned(LearnedItem item) {
  final actions = <InsightAction>[];

  final uri = item.url == null ? null : Uri.tryParse(item.url!);
  if (uri != null) {
    actions.add(InsightAction(
      label: item.amount != null ? 'Pay now' : 'Open',
      uri: uri,
      // `openLink` rather than `pay`: the recipe's own confidence does not
      // extend to promising a UPI handoff, and mislabelling the destination is
      // the thing the destination hints exist to prevent.
      kind: ActionKind.openLink,
    ));
  }

  final deadline = item.deadline;
  if (deadline != null && !item.isOverdue) {
    actions.add(InsightAction(
      label: 'Remind me',
      uri: _calendarReminderUri(item.label, deadline),
      kind: ActionKind.remind,
    ));
  }

  actions.add(openEmailAction(item.sourceEmailId));
  return actions;
}

/// Google Calendar day view for [date] — universal link, opens the app.
Uri calendarDayUri(DateTime date) => Uri.parse(
    'https://calendar.google.com/calendar/r/day/${date.year}/${date.month}/${date.day}');

const _joinLabels = <MeetingProvider, String>{
  MeetingProvider.meet: 'Join on Meet',
  MeetingProvider.zoom: 'Join on Zoom',
  MeetingProvider.teams: 'Join on Teams',
  MeetingProvider.webex: 'Join on Webex',
  MeetingProvider.other: 'Join meeting',
};

List<InsightAction> actionsForEvent(EventItem event) {
  final actions = <InsightAction>[];

  final joinUri =
      event.meetingUrl == null ? null : Uri.tryParse(event.meetingUrl!);
  if (joinUri != null && !event.isCancelled) {
    actions.add(InsightAction(
      label: _joinLabels[event.provider]!,
      uri: joinUri,
      kind: ActionKind.join,
    ));
  }
  actions.add(InsightAction(
    label: 'Open calendar',
    uri: calendarDayUri(event.start),
    kind: ActionKind.calendar,
  ));

  actions.add(openEmailAction(event.sourceEmailId));
  return actions;
}

List<InsightAction> actionsForAttention(AttentionItem item) {
  final actions = <InsightAction>[];

  final linkUri = item.linkUrl == null ? null : Uri.tryParse(item.linkUrl!);
  if (linkUri != null) {
    actions.add(InsightAction(
      label: 'Open link',
      uri: linkUri,
      kind: ActionKind.openLink,
    ));
  }

  actions.add(openEmailAction(item.sourceEmailId));
  return actions;
}
