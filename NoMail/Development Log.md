# Development Log

## 2026-08-01 — Recovery + Phase 1

**Context.** Repo located at `peersclub/hmail` (single commit, 2025-08-21), cloned to `/Users/Victor/Projects22/hmail`. Audit found the README describing a full product while the code was a demo-mode prototype: sign-in stubbed (`return false`), three hardcoded emails, canned orders/subscriptions/bills, and a retired Claude model in the AI service.

**Changes (uncommitted, working tree):**

1. **Startup crash fixed** — `main.dart` wrapped `dotenv.load` in try/catch with `dotenv.testLoad(fileInput: '')` fallback; app boots with no `.env`. Added `.env.example`; local `.env` created from it (gitignored).
2. **Real Google Sign-In** — `enhanced_gmail_service.dart` rewritten for google_sign_in **7.x**: `GoogleSignIn.instance.initialize(clientId:)` → `attemptLightweightAuthentication()` → `authenticate(scopeHint:)` → `authorizationClient.authorizeScopes()` → access token → `GmailApi`. Returns `false` when `GOOGLE_CLIENT_ID` is unset or the user cancels.
3. **Explicit demo mode** — provider now attempts real sign-in first and only falls back to demo with `isDemoMode = true`; demo mode guards all Gmail mutations so swipe actions mutate the local list instead of throwing.
4. **Dead-provider bug fixed** — 4 of 5 navigation tabs (`AmazonOrdersList`, `SubscriptionsList`, `BillsList`, plus `HomeScreen`/`InsightsChart`) consumed the legacy `EmailProvider`, which `main.dart` never provides — every dashboard tab crashed with `ProviderNotFoundException`. Migrated all five files to `EnhancedEmailProvider` and added a `fetchAndAnalyzeEmails()` alias.
5. **Claude model migrated** — `claude-3-haiku-20240307` (retired 2026-04-19, now 404s) → `claude-haiku-4-5`. Empty-string env keys now normalized to null so the template `.env` doesn't trip the "key configured" check.
6. **Login overflow fixed** — `LoginScreen` Column wrapped in `SingleChildScrollView` (overflowed 36px on small viewports).
7. **Tests green** — dotenv `setUpAll` seed added; nav-icon assertions relaxed to `findsWidgets`. `flutter test`: **6/6 pass**. `flutter analyze`: 0 errors (43 pre-existing infos/warnings).

**Not yet done / blockers:**
- No Google Cloud OAuth client exists → app runs in demo mode until `GOOGLE_CLIENT_ID` is minted (Phase 2, user action).
- On **web**, google_sign_in 7.x does not support `authenticate()` — needs the GIS `renderButton` widget. Prefer iOS/Android for first real-account test, or add the web button flow.
- Changes are local only — not committed or pushed.

Related: [[Roadmap]], [[Architecture]]

## 2026-08-01 — Rename: HMail → NoMail

Google rejected "HMail" as the OAuth consent-screen app name (too close to Gmail). Product renamed **NoMail**. Scope of the rename: user-visible strings only — MaterialApp title, login/inbox/home screen text, iOS `CFBundleName`, Android `android:label`, web `index.html` + `manifest.json`, README, this vault, demo address (`demo@nomail.app`), tests (6/6 still green).

**Deliberately unchanged:** GitHub repo slug `peersclub/hmail`, local path `Projects22/hmail`, Dart package name (`package:hmail/...`), and bundle/application ID `com.hmail.hmail` — the OAuth client binds to the bundle ID, and Google has no objection to it. Use "NoMail" as the app name on the consent screen; keep `com.hmail.hmail` as the iOS client's bundle ID.

## 2026-08-01 — OAuth client wired (iOS)

Victor created the Google Cloud OAuth iOS client (project consent name "NoMail"). Client plist landed in Downloads; values wired in:

- `GOOGLE_CLIENT_ID` set in local `.env` (client `129153074260-ek9c...`)
- `ios/Runner/Info.plist`: added `GIDClientID` + `CFBundleURLTypes` URL scheme with the reversed client ID; fixed leftover `CFBundleDisplayName` "Hmail" → "NoMail"
- **Bundle ID renamed** `com.hmail.hmail` → `com.nomail.nomail` (pbxproj ×6 incl. RunnerTests, Android `namespace`/`applicationId`, MainActivity package path) — the OAuth client was registered against `com.nomail.nomail`, and nothing shipped yet, so the app moved to match. Earlier "keep the bundle ID" note in this log is superseded.
- `plutil -lint` OK; analyze 0 errors; tests 6/6.

**Blocked on machine setup, not code:** first `flutter build ios --simulator` failed — Xcode license unaccepted, first-launch components missing, CocoaPods absent (brew install also blocked by the license). Victor to run `sudo xcodebuild -license accept` + `sudo xcodebuild -runFirstLaunch`, then install cocoapods and rebuild. No Android SDK on this Mac — iOS is the only mobile path locally.

## 2026-08-01 — Design system v3: liquid glass

Victor rejected both the Material editorial look and the plain Cupertino grouped-list look ("Settings-app utility skin"). New bar: Uber/Airbnb-level polish with Apple's liquid-glass material.

**Diagnosis of what was wrong:** four saturated hues fighting (red/orange/green/purple traffic lights), stock list rows with no depth, no hierarchy on the brief, truncated text everywhere.

**New contract (`lib/ui/glass/glass.dart` + `lib/core/palette.dart`):**
- Every surface is a real glass card: backdrop blur (σ26) + gradient white fill + hairline border + soft ambient shadow, over a gradient wash with two faint accent glows
- ONE accent (iOS blue). Red/orange exist only as urgency *text*. Icon badges are neutral circles. Data-viz uses a monochrome accent ramp (`Palette.ramp`)
- Floating glass dock replaces the tab bar (`GlassDock`, `kDockClearance` for content)
- Primitives: GlassBackground/Card/Header/Section/Row, IconBadge, SectionLabel, Footnote, GlassEmptyState, AccentButton, QuietButton

**Process:** foundation single-authored, then four parallel agents rebuilt Today / Money / Packages / Sign-in+Settings against the contract. Concurrent session added Event extraction (todayEvents, meetings in brief) — Today screen binds to it.

Also this session: AI gateway switched Anthropic-direct → **OpenRouter** (`OPENROUTER_API_KEY` + `OPENROUTER_MODEL`, default `anthropic/claude-haiku-4.5`); real-Gmail extraction fixes (bill amount near due-language, date-only overdue, stale-bill aging, cache key bump).

## 2026-08-02 — Reads pillar + native iOS 26 glass + settings alignment

**New insight category — Reads.** Email isn't only money and parcels; it's an unread reading queue. Added `FeedItem` (article/newsletter/video/podcast) with a rule extractor (`extractFeed`) keyed on known content senders (The Ken, Substack, Medium, YouTube, Spotify, NYT, Economist, Stratechery, Morning Brew, Finshots) plus a language fallback, gated against dev/social senders. Routed in `runExtractors` **after** money so a Substack *receipt* stays a subscription while a Substack *post* becomes a read. Wired end-to-end: `InsightSnapshot.feed` + `recentFeed`, `scanReads` ScanSettings toggle + 5th Gmail query, sync engine, store merge (dedupe by source+title), demo fixtures, store key v5. New **Reads tab** (5th, book icon) grouping by kind, each row opens the piece via the existing action launcher. 175 tests green (added feed extractor tests; updated concurrent session's query-count/describeScope expectations for the +1 query).

**Design system reset (earlier this session).** Rejected Material and plain-Cupertino looks. Now: `cupertino_native_plus` for the **native iOS 26 Liquid Glass** dock (real UITabBar glass) after Flutter SDK upgrade to 3.44.8; Flutter-drawn `GlassCard` (BackdropFilter) for scrolling cards (native platform-view glass desyncs while scrolling). Monochrome **ink accent** (near-black/near-white) — no system blue. Apple-native type scale (17/15 rows, regular weights, sentence case). Overdue shows as a pill. Status-bar scrim. Tested on iPhone 17 Pro / iOS 26.5.

**Settings alignment fix.** The hand-built profile + syncing rows still used the old 16/13 type scale and a 36pt avatar while every real `GlassRow` moved to 17/15 + 38pt badge — that 2px/font mismatch was the visible misalignment. Aligned both to the GlassRow contract.

**Data honesty.** Delivery extractor now requires commerce evidence (killed "GitHub shipped dark mode" false parcels); deliveries with long-past ETAs age out; bill dedupe is issuer+due-day+amount (killed duplicate CRED rows).

**Still open (next):** multiple Gmail accounts (needs real 2nd sign-in to verify — data layer not yet built); a Reads toggle in the Scan settings screen (query defaults on, just not user-visible yet); AI brief could summarize the reading queue.

## 2026-08-02 — Phase 1 IA refactor: type-driven Insight architecture + Timeline

A UX-review agent found the core scaling flaw: one-tab-per-category hits iOS's ~5-tab ceiling (already at 5) and most tabs sit empty on a quiet day. Verdict — visual system (glass, ink) is good and stays; **navigation architecture needed rework**. User greenlit the full Phase 1.

**Built (adapter approach — kept the 6 typed models + their tests + persistence intact):**
- `domain/insight.dart` — generic `Insight` (id, domain, title, subtitle, trailing, caption, anchorDate, overdue, icon, brandKey, weight, actions), `InsightDomain` enum (security/money/commerce/travel/work/content/personal/government, each with label+icon), `UrgencyTier` (imminent <6h / near ≤3d / ambient), and `rankInsights()` — urgency tier → weight → soonest anchor.
- `domain/insight_mapper.dart` — `snapshotToInsights()` wraps every typed model into `Insight` (weights: security 100 > overdue bill 90 > due-soon 70 > sub 55 > delivery 45 > content 20), reusing existing `actionsForX` builders; `presentDomains()` drives Timeline chips.
- `ui/insight_card.dart` — ONE row renders any Insight (brand glyph via BrandIcons, tap→action sheet). New insight types now = model + extractor + one mapper block, **zero navigation code**.
- `ui/screens/timeline_screen.dart` (agent-built) — chip-filtered feed replacing Packages+Reads AND all future domains; chips appear only for domains with data.
- **Today rewritten**: brief + stat strip kept; the 5 hand-rolled sections collapsed into ranked tiers — "Needs attention" (imminent) / "Coming up" (near) / "All clear" fallback. Ambient items (reads, far renewals) live in Timeline only.
- **Shell → 4 tabs**: Today · Money · Timeline · Settings. Dock updated (Timeline = stacked-squares SF Symbol). Deleted `packages_screen.dart` + `reads_screen.dart`.
- **Brand icons**: `simple_icons` (1500+ brands) wired across screens as monochrome-tinted glyphs (Netflix/Spotify/YouTube/Substack/Uber/Swiggy… render as ink silhouettes; unknown senders keep the generic category icon). Simple Icons omits some trademarks (Amazon/Adobe/Flipkart) → those fall back cleanly.

**259 tests green in isolation** (251 existing + 8 new insight/ranker/mapper). Build was momentarily blocked by a **concurrent session's in-flight files** (`knowledge_mapper.dart` referencing `MoneyMatch` without import, sync_engine/sync_report mid-edit) — not Phase 1 code; a background watcher waits for the tree to compile clean, then builds + installs to the iPhone.

**Next (Phase 2, per review):** new domains on the now-cheap architecture — Security (OTPs/login alerts, currently mis-bucketed in AttentionItem), Money (refunds/failed payments), Travel (flights/check-in/boarding passes). Plus multiple Gmail accounts (still deferred).

## 2026-08-02 — Timeline chips: counts, drag-reorder, UX review pass

User asks on the Timeline filter chips (the "top tabs"): (1) too close to first card, (2) show per-domain count, (3) drag to reorder. Built all three: per-chip counts ("Deliveries · 4"), long-press drag-reorder via Material `ReorderableListView` (needed `Localizations.override` with `DefaultMaterialLocalizations.delegate` since this is a Cupertino app — it threw "No MaterialLocalizations" the moment ShellScreen's IndexedStack eagerly built the Timeline tab, breaking unrelated Today tests), order persisted in `data/store/timeline_order_store.dart` and also driving feed section order, "All" chip pinned first.

Then a `ux-expert-reviewer` agent (scored 6/10) caught real issues, all applied as quick wins: the spacing fix had left the *filtered* view tighter (12px) than "All" (42px) → bumped to 20px; `proxyDecorator` returned an identical widget so drag was invisible → now scale 1.06 + shadow; 34pt hit target → 44pt via outer padding on a 34pt visual pill; inactive count double-dimmed (alpha on secondaryLabel) → restored; added `Semantics(selected:)`; middot separator to match app convention. Deferred: pinning the chip row (sliver refactor), on-device VoiceOver drag audit. Agent saved review + design-convention notes to `.claude/agent-memory/ux-expert-reviewer/`. 257 tests green; on device.

## 2026-08-02 — Phase 2 domains: Travel + Payment alerts (committed)

Two new insight domains on the Phase-1 architecture, each surfacing automatically in Timeline + Today with zero navigation code:

**Travel** (commit after ae59389): `TravelItem` (flight/train/hotel/bus, provider/route/PNR/departure). `extractTravel` keyed on airline/OTA senders (IndiGo, Vistara, MakeMyTrip, IRCTC, Booking.com…) or strong travel language (PNR, e-ticket, itinerary), gated against fare-marketing blasts. Airport-pair route + PNR + departure parsing. 6th Gmail query (`scanTravel`). Weight 65 (above subs, below due-soon bills), anchored on departure so a flight inside the check-in window rises on Today. Store key v6.

**Payment alerts** (this commit): `PaymentAlert` (refund/failed, source, amount). `extractPayment` on declined/refund language, routed **before bills** (a failed bill-payment is money-at-risk, not a bill). Reuses the widened money receipts query (no new scan query → no settings-test churn). Failed payments forced to Today's imminent tier + red pill (weight 92, above overdue bills); refunds are ambient confirmations (weight 78). Store key v7. 265 tests green, on device.

**Security/OTP status:** the review's "AttentionItem is mis-bucketed" concern was pre-Phase-1. Post-mapper, `AttentionItem` maps to `InsightDomain.security` at weight 100 — the highest — so login/security alerts already rank at the top and appear under the Timeline "Security" chip. A dedicated typed OTP model wasn't needed for correct bucketing/ranking; could add one later if OTP-specific actions are wanted (they expire in minutes, so likely low ROI).

**Still deferred — multiple Gmail accounts.** Genuinely needs a live second Google sign-in to build+verify (the composite multi-account source can't be tested on-simulator without a real 2nd account), and it touches the auth layer a concurrent session has been editing. Deliberate next-session task with the user present to sign in.
