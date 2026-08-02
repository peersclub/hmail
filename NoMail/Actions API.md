# Actions API — contextual actions for every insight

> Part of [[Architecture]]; the product reasoning is in [[One App Vision]] and
> the destination-app work is tracked in [[Roadmap]].

> Written 2026-08-01 by the core-functionality agent, for whichever agent/human wires up the UI.
> Everything here is implemented, unit-tested (`test/actions_test.dart`, 38/38 passing with the
> existing extractor suite), and pure Dart except the launcher.

## What was added

Every insight type now carries enough context to **act**, not just read:

| Insight | Primary action | Fallbacks |
|---|---|---|
| `Delivery` | Track package — exact tracking link lifted from the email | carrier URL template → 17track universal tracker → Open email |
| `Bill` | Pay now / Pay via UPI — pay link or `upi://` intent from the email | "Remind me" (Google Calendar entry on due date) → Open email |
| `Subscription` | Manage plan — manage/cancel link from email or known service billing page | Open email |
| `EventItem` (**new**) | Join on Meet/Zoom/Teams/Webex | Open calendar (day view) → Open email |
| `AttentionItem` | Open link (verify/review/reset link from the email) | Open email |

"Open email" always exists — `https://mail.google.com/mail/u/0/#all/<messageId>` is a
universal link, so it opens the Gmail app when installed.

## How the UI consumes it

```dart
import 'package:hmail/domain/actions.dart';
import 'package:hmail/core/action_launcher.dart';

final actions = actionsForDelivery(delivery);   // ordered best-first
// also: actionsForBill / actionsForSubscription / actionsForEvent / actionsForAttention

// render actions as buttons / swipe actions; on tap:
final ok = await openAction(actions.first);
if (!ok) { /* offer actions.last — Open email — as fallback */ }
```

`InsightAction` is `{label, uri, kind}`; `kind` (`track|pay|remind|manage|join|calendar|openLink|openEmail`)
is there so the UI can pick icons. The builders are pure — safe to call in `build()`.

## Calendar / meetings (new pipeline branch)

- `EventItem` model in `domain/models.dart`: title, organizer, start/end, meetingUrl,
  provider, location, `isCancelled`; `snapshot.events`, `snapshot.todayEvents`,
  `snapshot.upcomingEvents`.
- Extraction in `data/extractors/events.dart`: Google Calendar invite subjects
  ("Invitation: X @ Mon Aug 3, 2026 3pm - 3:30pm"), Zoom/Teams/Webex invite bodies,
  cancellations, dedupe across "Updated invitation" emails.
- Gmail source has a 4th query for invites (`filename:ics`, `subject:invitation`, ...).
- The daily brief now includes meeting insights: "3 meetings today (some back-to-back)",
  per-meeting bullets with times and "join link ready".

## Phase A additions (2026-08-01, second batch)

- **`BackfillStats.fromSnapshot(snapshot)`** (`lib/domain/backfill_stats.dart`) — the onboarding
  "money shot": `annualRecurringDisplay` ("₹18,400/yr"), `headline` ("Found 9 subscriptions
  costing ₹18,400/yr, 3 bills due, and 2 packages on the way."), plus counts for a stat row.
  Pure Dart, render it on the first post-scan screen.
- **`NotificationService`** (`lib/core/notification_service.dart`) — call `await init(onTap: router)`
  after first frame; after every sync call `scheduleDailyBrief(snapshot.brief!)` (8am daily,
  cancel-and-replace). Tap payloads: `'brief'` → Today screen; `'action:<id>|<payload>'` →
  split on first `|` (`pay`/`remind`/`track`/`join`). Degrades to no-op if permission denied.
- **India coverage**: extractor maps now recognize ~75 additional Indian senders (electricity
  boards, gas, DTH, card issuers, insurers, XpressBees/Ecom Express/India Post/Shadowfax,
  Meesho/Zepto/Blinkit/JioMart..., SonyLIV/Zee5/JioHotstar...). Subscriptions Gmail query
  widened to 365d so annual renewals appear in the first scan.

## Other notes for the UI pass

- Storage key bumped `insight_snapshot_v2 → v3` (forces clean re-extract; old cached
  snapshots without link fields are discarded on next sync).
- New dep: `url_launcher ^6.3.1` (already in pubspec, `pub get` run).
- All link fields are nullable — never assume a deep link exists; the actions builders
  already handle absence, so prefer rendering from `actionsForX()` rather than reading
  `trackingUrl`/`payUrl` directly.
- A natural Today-screen addition: a "Meetings" section fed by `snapshot.todayEvents`
  with the join button as the row's primary action.
