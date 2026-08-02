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
│   ├── scan_settings.dart        # user-controlled scan scope
│   ├── sync_report.dart          # per-sync receipt + AI audit summary
│   └── backup_bundle.dart / backup_prefs.dart
├── data/
│   ├── mail/                     # gmail_auth (multi-account + resilient
│   │                             # client), gmail_source, multi_gmail_source,
│   │                             # mail_source (+ DemoMailSource fixtures)
│   ├── extractors/               # extractors.dart, events.dart, links.dart
│   ├── ai/                       # insight_ai (interface + verdicts),
│   │                             # openrouter_ai, knowledge_learner, ai_status
│   ├── store/                    # insight, knowledge, settings,
│   │                             # backup_prefs, timeline_order
│   ├── backup/                   # backup_service + Drive/iCloud targets
│   └── sync/sync_engine.dart     # the pipeline
├── core/                         # palette, brand_icons, action_launcher,
│                                 # notification_service
└── ui/
    ├── glass/glass.dart          # the design system (every surface)
    ├── insight_card.dart         # ONE row renders any Insight
    ├── action_sheet.dart
    └── screens/                  # today, money, timeline, settings,
                                  # ai, scan, processing, knowledge, sign_in
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
4. **Merge** — `InsightStore.merge` dedupes against the previous snapshot by
   natural key, keeping the most recent version of each insight.
5. **Audit (AI, optional)** — the model sees the extracted insights next to
   their source emails and returns `InsightVerdicts {rejected, renamed}`,
   applied by the pure `applyVerdicts()`. It also writes the daily brief.
6. **Learn (AI, optional)** — anything still unrecognised is clustered by
   sender and offered to `KnowledgeLearner`, which writes new playbook
   recipes. These take effect from the *next* sync.
7. **Save** — snapshot to `InsightStore`, new recipes to `KnowledgeStore`.

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

Related: [[Requirements]], [[Roadmap]], [[Settings Plan]], [[Actions API]],
[[One App Vision]], [[Development Log]]
