# Architecture

Flutter (iOS-first), Provider for state. The whole app is one use-case —
**mail in, ranked actionable insights out** — so the layering follows that
pipeline rather than MVC-by-folder.

> The pre-2026-08-01 structure (`models/`, `providers/`, `services/`,
> `screens/`, `widgets/`) is gone. Nothing below is a plan; it is what's on
> disk.

## Layout

```
lib/
├── main.dart                     # dotenv load → AppController → NoMailApp
├── app/nomail_app.dart
├── state/app_controller.dart     # the only ChangeNotifier: phase, snapshot,
│                                 # settings, playbook, live sync stage
├── domain/                       # pure Dart, no Flutter, fully unit-tested
│   ├── models.dart               # Subscription, Bill, Delivery, EventItem,
│   │                             # TravelItem, PaymentAlert, FeedItem,
│   │                             # AttentionItem, InsightSnapshot
│   ├── insight.dart              # generic Insight + InsightDomain +
│   │                             # UrgencyTier + rankInsights()
│   ├── insight_mapper.dart       # typed models → Insight (weights/ranking)
│   ├── actions.dart              # InsightAction builders per insight type
│   ├── knowledge.dart            # the learned playbook (see below)
│   ├── knowledge_mapper.dart     # learned match → typed insight
│   ├── brief_builder.dart        # deterministic daily brief
│   ├── backfill_stats.dart       # first-scan "hiding in your inbox" summary
│   ├── price_watch.dart          # price-hike detection (pre-merge diff)
│   ├── ignore_list.dart          # the user's corrections ("not a bill")
│   ├── scan_settings.dart        # user-controlled scan scope
│   ├── scan_cost.dart            # pre-scan estimate from live model pricing
│   ├── sync_report.dart          # per-sync receipt + AI audit summary
│   └── backup_bundle.dart / backup_prefs.dart
├── data/
│   ├── mail/                     # gmail_auth (multi-account + resilient
│   │                             # client), gmail_source, multi_gmail_source,
│   │                             # mail_source (+ DemoMailSource fixtures)
│   ├── extractors/               # extractors.dart, events.dart, links.dart
│   ├── ai/                       # insight_ai (interface + verdicts),
│   │                             # openrouter_ai, knowledge_learner, ai_status
│   ├── store/                    # insight, knowledge, settings, ignore,
│   │                             # link_feedback, backup_prefs, timeline_order
│   ├── backup/                   # backup_service + Drive/iCloud targets
│   └── sync/sync_engine.dart     # the pipeline
├── core/                         # palette, brand_icons, action_launcher,
│                                 # notification_service, upcoming_alerts,
│                                 # installed_apps, host_routing
└── ui/
    ├── glass/glass.dart          # the design system (every surface)
    ├── insight_card.dart         # ONE row renders any Insight
    ├── action_sheet.dart
    └── screens/                  # today, money, timeline, settings, ai, scan,
                                  # processing, knowledge, corrections,
                                  # backup, web_view, sign_in
```

## The pipeline

`SyncEngine.runReported()` is the spine. Order matters:

1. **Fetch** — `GmailSource` runs one targeted Gmail query per enabled domain
   (receipts, bills, packages, meetings, reads, travel), then one request per
   message. Progress is reported as human sentences ("Reading packages · 15 of
   50").
2. **Extract** — `runExtractors()` applies hand-written rules. Deterministic
   parsing beats an LLM for machine-generated mail: free, instant, offline,
   testable.
3. **Apply knowledge** — the learned playbook runs over whatever the rules
   didn't claim. Still no model, still free.
4. **Watch prices** — `detectPriceChanges` diffs the previous snapshot's
   subscriptions against the fresh ones. This has to happen *before* step 5,
   because merge collapses subscriptions by service name and the old amount
   stops existing. See "Price watch" below.
5. **Merge** — `InsightStore.merge` dedupes against the previous snapshot by
   natural key, keeping the most recent version of each insight.
6. **Audit (AI, optional)** — the model sees the extracted insights next to
   their source emails and returns `InsightVerdicts {rejected, renamed}`,
   applied by the pure `applyVerdicts()`. It also writes the daily brief.
7. **Learn (AI, optional)** — anything still unrecognised is clustered by
   sender and offered to `KnowledgeLearner`, which writes new playbook
   recipes. These take effect from the *next* sync.
8. **Save** — snapshot to `InsightStore`, new recipes to `KnowledgeStore`.

Afterwards the controller rebuilds the proactive alert schedule from the fresh
snapshot (`buildUpcomingAlerts`) — renewal T-2d, bill T-1d, return window T-1d.
It is rebuilt from scratch every sync rather than maintained: the builder is
pure and the scheduler cancels its own id namespace first, so a bill that got
paid simply stops being scheduled.

Every AI step is optional and never fatal: with no key, or the AI switch off,
rules carry the whole load and a rule-built brief always exists.

## The learned playbook

The app writes its own handling rules rather than shipping one per merchant.
A `ContentType` is data: a `ContentMatcher` (sender domains / subject terms /
required body terms), `FieldRule`s (regex with one capture group), and
`ActionTemplate`s (`https://…/track/{trackingNumber}`). Once learned, it is
applied deterministically forever — so the app gets **smarter and cheaper**
with use.

Because a language model authors these, the engine treats them as hostile: a
matcher with no sender domain can never match; regexes must compile with
exactly one capture group and are probed to reject catch-alls; declared
domains must appear in the emails the recipe was learned from; templates must
be `https:` or `upi:`; a template missing a field yields nothing rather than a
URL containing a literal `{placeholder}`. Invalid entries are dropped with a
reason. Users see every recipe under Settings → Knowledge and can disable or
forget it; disabled ones still count as "known" so the learner never pays to
rediscover a rejected recipe.

## Price watch

`domain/price_watch.dart` diffs two snapshots' subscriptions to find "Netflix
went ₹649 → ₹699". Two design points carry the whole feature.

**It must run before the merge.** `Subscription.dedupeKey` is just the lowercased
service name, so `InsightStore.merge` keeps one row per service — after it runs,
the old amount is gone from every store in the app. The detector also reuses
merge's own collapse rule (latest `lastSeen` wins) so the "new" price it reports
is always the number the Money tab will render; a different rule would let the
two disagree.

**One wrong price claim costs more trust than ten right ones earn**, so each
guard exists to kill a class of false hike: same currency and cadence, a
*different* source email (an extractor fix changing what one email yields is not
a merchant raising a price), newer evidence only (a backfilled receipt must not
read as a hike running backwards), and floors of both 1% and one minor unit.
`applyVerdicts` extends to price changes too — a change is only as real as the
subscription it was measured on.

The Money hero shows the net monthly drift, and deliberately does **not** call it
"savings". The app can prove a price moved; it cannot prove the user cancelled
anything. Overclaiming here would cost exactly the trust that makes the number
worth reading.

## Corrections

`domain/ignore_list.dart` is the user's veto. Extraction is heuristic, so it is
permanently wrong about something, and before this the user had no way to say so.

A rule is `(IgnoreKind, subject)` — not an email id — because "GitHub is not a
delivery" has to still be true next week when GitHub sends another release note.
The subject is the name the extractor already derived from the sender, which is
the granularity a user means when they tap "Not a package". Matching is exact: a
substring rule would let "Amazon" silence "Amazon Pay".

`applyIgnores` runs on the way **out** of the store, in `AppController.snapshot`,
never on the way in. So undoing a correction restores its insights instantly with
no rescan, and the raw snapshot that feeds the next sync's merge still sees
everything. Rules live in their own store key rather than inside the snapshot —
they are user intent, and a snapshot version bump must never discard them. They
ride in the backup bundle for the same reason the playbook does: a rescan
re-derives insights but not decisions.

## Where a tap goes

Every action resolves to one of three destinations, decided by
`domain/deep_links.dart`:

1. **The native app** — when a probe found it. `core/installed_apps.dart`
   tests ~45 custom schemes once per session (declared in
   `LSApplicationQueriesSchemes`, iOS caps this at 50) and caches the result;
   the sweep is warmed at startup so a sheet never waits on it.
2. **An in-app WebView** — public pages, kept inside NoMail so we can ask
   whether the link was right.
3. **iOS** — non-http schemes, payments, and anything behind a login.

Four constraints shape that, and each one cost a bug to learn:

- **iOS cannot tell you whether an app claims an https URL.** `canLaunchUrl`
  on https always says yes, because Safari can open it. So detection runs on
  custom schemes while the thing we *launch* stays the https universal link —
  which matters because of only 44 catalogued apps just 5 publish a
  documented launch format. No Indian courier or merchant does, so a
  constructed `delhivery://…` would fail silently where the universal link
  works.
- **A WKWebView has no cookies.** Gmail, banks and billing pages render
  logged-out inside it, which is indistinguishable from a broken link — and
  would have users voting down correct URLs. Known auth hosts never reach the
  WebView; unknown ones are caught on arrival by the landed URL and title and
  recorded as `loginWall`, which is explicitly *not* counted against a recipe.
- **A WKWebView never fires universal links.** Rendering an unknown
  merchant's page in-app therefore *guarantees* bypassing their app. The fix
  is memory rather than a bigger registry (which iOS caps anyway):
  `core/host_routing.dart` remembers hosts the user tapped "open outside" on,
  and hands them to iOS forever after.
- **Say where a tap goes before it is taken.** Each sheet row ends with the
  app's mark and name, a globe for "stays in NoMail", or an out-arrow for
  "leaves" — via the pure `destinationHint()`.

`domain/link_feedback.dart` closes the loop: a thumbs-down on a page marks
the learned recipe that produced the URL as suspect (≥2 failures, no
successes), which is the only signal that a template the AI wrote is wrong.

## Presentation

Typed models are mapped once into a generic `Insight` (domain, weight,
anchor date, actions) and ranked by `rankInsights()`: urgency tier
(imminent < 6h, near ≤ 3d, ambient) → weight → soonest anchor. `InsightCard`
renders any of them. **Adding an insight type is a model + extractor + one
mapper block — zero navigation code.**

- **Today** — brief, stat strip, "Needs attention" (imminent) / "Coming up"
  (near). Ambient items live in Timeline only.
- **Timeline** — chip-filtered cross-domain feed; chips show counts and are
  drag-reorderable (order persisted).
- **Money** — recurring hero + subscriptions + bills.
- **Settings** — the trust surface: see [[Settings Plan]].

## Key decisions & gotchas

- **Rules first, AI second, learned rules in between.** The AI's job is to
  audit, to write the brief, and to *author new rules* — not to be in the hot
  path of every insight.
- **google_sign_in is v7.x** — `GoogleSignIn.instance`, `authenticate()`,
  `authorizationClient`. Most samples online are v6; they do not apply.
- **The Gmail client must survive a long scan.** Hundreds of sequential
  requests on one keep-alive connection produce `ClientException: Bad file
  descriptor` when a socket is reclaimed. `_BearerClient` retries on a fresh
  connection (rebuilding the request — a `BaseRequest` can only be sent once)
  and re-fetches the access token on a 401, since tokens expire hourly. A
  single failed message or query is skipped, not fatal; total failure throws,
  because an unreachable Gmail must not render as "your inbox is empty".
- **Extractor map order is load-bearing** — specific keys before generic
  (`tatapower` before `power`, `hdfcergo` before `hdfc`). Dart maps iterate in
  insertion order, which is the priority system.
- **A wrong link is worse than none.** Action URLs are scored by proximity to
  action language and suppressed below a confidence floor, falling back to
  opening the source email in Gmail.
- **flutter_dotenv loads `.env` as a bundled asset**, so API keys ship inside
  the IPA. Fine for personal builds; must move behind a server-side proxy
  before distribution.
- **Store keys are versioned** and bumped whenever extraction changes
  materially, forcing a clean re-extract instead of merging onto stale data.
  Currently `insight_snapshot_v9`. User *decisions* — corrections, learned
  recipes — live in their own keys precisely so a bump can't throw them away.
- **Never ship a number the app can't defend.** The scan cost estimate reads
  live prices from OpenRouter's models endpoint rather than a table in the
  build, and reports no money at all when that fails; the Money drift line says
  "vs before", not "saved". Both screens exist to be trusted, and a stale or
  overclaimed figure costs more than a missing one.
- **The iPad is a real device, not a wide phone.** The glass system was drawn
  for phone widths, so `ReadableWidth` (560pt) caps page content and
  `showSheet` (480pt) caps every popup. The cap sits just above an iPhone Pro
  Max so it is provably inert on phones — a test asserts that, because silently
  narrowing the iPhone layout would be worse than the stretch this fixed. The
  WebView keeps full width on purpose: sites are responsive, and a wide
  viewport is what an iPad is *for*.

Related: [[Requirements]], [[Roadmap]], [[Settings Plan]], [[Actions API]],
[[One App Vision]], [[Development Log]]
