# Development Log

## 2026-08-04 — ui-ux-pro-max audit: all 4 waves shipped

Full audit + execution log in [[UX Backlog — ui-ux-pro-max audit]]. 14 items, 4 commits:

- **Wave 1 (`aec9fd2`)** — `PressableRow` in glass.dart: press feedback (<100ms opacity dim, no layout shift) + VoiceOver button semantics for every tappable row app-wide. 44pt touch targets (SyncBusyBadge, WebView open-outside/pill/dismiss). Labels on icon-only buttons.
- **Wave 2 (`c39d7c4`)** — Reduced Motion gating (Money count-up 700→450ms, zero under system setting; WebView hairline). `SkeletonRows` during first scan on Today + Money. Haptics on backup success / restore / account connect.
- **Wave 3 (`5456b03`)** — Timeline grouped feed = lazy `SliverList` of keyed domain sections (blur budget flat; rows keyed by `insight.id`). GlassRow +1 text line at accessibility sizes. `tertiaryLabel`→`secondaryLabel` for informational text (AA contrast). `GlassEmptyState` action slot.
- **Wave 4 (`bf79b1c`)** — `AiKey`: in-app OpenRouter key entry (Settings → AI, Add/Replace/Remove; user key beats .env; SharedPreferences with documented trade-off). Daily-brief notification deep-links to Today (`tabRequest` + shell listener).

Deferred: #13 icon sweep (remaining fill/outline mixes are semantic). Needs device: VoiceOver pass, largest-AX-size pass, contrast on real blur.

371 tests pass; installed to iPhone.

## 2026-08-02 — Multi-account managed properly (commit `b6e9438`)

Victor: "I still feel like multiple Gmail account addition is not managed better." An audit agreed — and found a bug on the way.

**Bug fixed first (`d7d8c81`):** "Open email" had been broken for every real account since multi-account landed — the `a0:`/`a1:` id prefix was baked into the Gmail URL. Now stripped and mapped to Gmail's `/mail/u/<N>/` authuser slot, so account B's email opens in account B's inbox.

**P0 — accounts survive restarts.** google_sign_in 7.x restores only the single active platform session at boot, so added accounts silently vanished on relaunch. New `AccountsStore` (`connected_accounts_v1`) remembers them; disconnected ones surface as dimmed **"Session ended — tap to reconnect"** rows. Reconnect drives the Google sheet and narrates honestly if the OS returns a different account.

**P1 — narrated add-account.** `AddAccountResult` (added / alreadyConnected / failed) → in-flow lines under the Accounts rows: "Connected x@…", the already-connected guidance (explains "Use another account" in Google's sheet — the iOS re-offer quirk), or the failure with retry.

**P1 — per-account sync health.** `MultiGmailSource.lastFailures` records which inbox failed and why (401 → "remove and reconnect"); account rows show it in destructive text after each sync — no more silently stale inboxes.

**P1 — attribution.** With 2+ accounts, insight action sheets say "From x@gmail.com" (`accountForInsight` maps the `aN:` prefix). Suppressed with a single account (noise).

**P2s deferred:** surgical removal (still clear+rescan), scan-estimate × account count, backup multi-account awareness. **Still needs Victor's device:** the live second-account picker test.

322 tests pass; installed to iPhone.

## 2026-08-02 — App-wide user-journey overhaul

Victor's verdict on the first backup UX ("I click back up… somewhere in the bottom shows Google drive backup failed") triggered a journey pass over the whole app: **feedback must render on the control the user tapped, name its cause, and offer the recovery.**

**Backup journey (rewritten).**
- `GmailAuth.driveApi` now returns `(api, issue)` — notSignedIn / notGranted / declined / failed — and `DriveBackupTarget` maps every failure to a cause+recovery message ("Permission was declined… tap again and choose Allow", 403 accessNotConfigured → "enable the Drive API in Cloud Console", 401 → re-sign-in, network → check connection). Generic "backup failed" is banned.
- Controller: `BackupActivity` (idle/backingUp/checking/restoring) + **scoped** error/notice (`BackupErrorScope.backup|restore`) so results render inline directly under Back Up Now or Restore. Success is an in-flow ✓ line (no modal). First-backup hint pre-announces Google's one-time consent sheet.
- Restore is staged: tap → fetch (interactive) → confirm dialog showing device/date/size/**counts** → apply → inline "Restored N insights". `prepareRestore`/`confirmRestore`/`cancelRestore`.
- Auto-backup is now strictly silent: runs only when the target `isAuthorized()` (no surprise consent sheets) and swallows failures.
- Demo mode shows the *path* (Exit Demo & Sign In action) instead of a dead-end notice. iCloud row honestly says "Not available in this build yet" (personal-team limit) instead of pointing at a nonexistent iOS setting.

**App-wide fixes from a 10-point UX audit** (agent-audited, files:lines in the audit record):
1. Sync/account errors now render inside Settings under the row that failed (destructive text + retry), not only as a gray footnote on Today.
2. Silent action failures fixed: Pay/Track/Join now fall back to the insight's email when no app can handle the deep link (`_launchWithFallback` in action_sheet.dart).
3. Sign-in flash fixed: `signIn()` keeps phase `signedOut` during OAuth (new `authenticating` flag) so the sign-in screen stays mounted with "Connecting to Google…" — no more empty-shell flash + bounce on cancel.
4. Sign Out / Exit Demo now confirm via action sheet (it clears the local cache; account-removal already confirmed — inconsistency removed).
5. Rescan row no longer promises "with AI" when AI is off/unkeyed.

**Tab screens (parallel agent).** Sign-in: in-place progress + inline error + honest "Explore with Sample Data". Today: scanning state with live `activityLine`, error row with Try again, empty state with a real Scan button (not just pull-to-refresh prose). Timeline: per-domain empty lines. Money: syncing narration + scan CTA. New shared `lib/ui/widgets/journey_states.dart` (BusyLine, ScanActionButton).

**Audit follow-ups done same day:** #3 — shared `SyncBusyBadge` (tap → live pipeline) now on Today/Money/Timeline headers; #8 — a vanished chip filter now says "<Domain> is empty now — showing everything" instead of silently resetting (choice kept, re-applies if the domain refills). **Still open:** #4 AI-key entry vs honest copy for shipped builds (needs a product call); #9 GlassEmptyState action slot (covered in practice by ScanActionButton).

**Apple Developer Program:** Victor enrolled (Individual, US account) — activation pending. When active: switch project team, add iCloud capability + `iCloud.com.nomail.nomail`, rebuild → iCloud backup goes live, and the 7-day free-team app expiry disappears.

297 tests pass (backup journey + Drive message mapping + controller state tests added); analyze clean; installed to iPhone.

## 2026-08-02 — WhatsApp-style backup & restore (iCloud + Google Drive)

Full backup system for NoMail's knowledge + insights. See **[[Backup & Restore]]** for architecture and the two enablement steps.

- **Bundle** — `BackupBundle` aggregates all four stores (`snapshot`/`playbook`/`settings`/`timelineOrder`) into one versioned JSON doc. The playbook (AI-earned recipes) is the piece a rescan can't rebuild, so it's the real reason to back up.
- **Targets** — `BackupTarget` interface + `DriveBackupTarget` (Drive `appDataFolder`, hidden per-app folder, reuses Google Sign-In with an added `drive.appdata` scope via `GmailAuth.authorizeDrive`), `ICloudBackupTarget` (native `MethodChannel` → `AppDelegate.swift`, ubiquity container), `MemoryBackupTarget` (tests/null).
- **Service** — `BackupService.collect/restore`; restore rehydrates the stores and `AppController._reloadFromStores()` refreshes in-memory state so the UI updates at once.
- **When** — `BackupPrefs` Off/Daily/Weekly; auto-backup is **opportunistic after a sync** (no phone daemon). `AppController._maybeAutoBackup`.
- **UI** — Settings → **Backup** screen (last-backup status, Back Up Now, destination picker, frequency, Restore with an overwrite confirm).
- **Native** — iCloud handler inline in `AppDelegate.swift` (no fragile pbxproj edit). Degrades to "unavailable" until the iCloud capability is added in Xcode, so the build stays green today.

**Two enablement steps needed (Victor's accounts):** (1) add `drive.appdata` to the OAuth consent screen + enable the Drive API; (2) add the iCloud capability + container `iCloud.com.nomail.nomail` in Xcode. Details in [[Backup & Restore]].

288 tests pass (new `backup_service_test.dart`), analyze clean, release build signed + installed to the iPhone.

## 2026-08-02 — Boarding passes / check-in windows

Extended the **travel** domain (no new domain, no native code) so the pressing moment — *check-in open now / boarding pass ready* — outranks a distant confirmed flight.

- `TravelItem.boardingReady` (additive bool, default false; JSON round-trips).
- `extractTravel` sets it on "check-in is (now) open", "boarding pass", "download your boarding pass", etc. The future-tense "web check-in **opens** 48 hours before" is deliberately **not** matched, so a plain confirmed flight doesn't escalate.
- Mapper: when `boardingReady`, weight 65 → **80**, subtitle "Check-in open", icon `ticket_fill`, primary action "Check in".
- Demo fixture: IndiGo "Web check-in is now open" (PNR Z8M3T1, distinct from the confirmed-flight fixture so they don't dedupe). Two extractor tests pin the open-vs-future distinction.

The **full PassKit / `.pkpass` "Add to Apple Wallet"** flow remains the one genuinely native follow-up — this ships the user-facing value (check-in escalation + right action) without it.

283 tests pass, analyze clean, reinstalled to the iPhone.

## 2026-08-02 — Multi-account + Returns/warranty domain (commit `fb70aae`)

Two subsystems landed in one commit, plus a regression fix.

**Returns/warranty domain (new `InsightDomain.commerce` items).** Followed the adapter recipe end-to-end with zero navigation/screen changes:
- `ReturnItem` model (`returnWindow` | `warranty`), deadline + `isStale` (past by >1 day) + dedupe by kind/merchant/deadline-day.
- `extractReturn`: only fires when a deadline is parsed *near* the return/warranty phrase, so footer "easy returns" boilerplate is ignored. Routed **before** `extractDelivery` so a "delivered, return by X" email surfaces as an actionable return, not an inactive delivery.
- Deliveries Gmail query widened with `return`/`warranty` (no new query → no scan-settings churn). Mapper block (weight 58, `arrow_2_squarepath`/`shield` icons, Start-return / View-warranty actions). Sync build + `applyVerdicts` passthrough. Store merge + key `v7` → **`v8`**. Demo fixtures: Myntra return window, boAt warranty.

**Multi-account Gmail** (built by a parallel agent, verified green): `GmailAuth` now holds `List<GmailAccount>` with `addAccount`/`removeAccount`/`signOutAll` (dedupe by email); new `MultiGmailSource` fans out one `GmailSource` per account and prefixes ids `a0:`/`a1:` to prevent cross-account collisions; `AppController` accounts API; Settings **Accounts** section with per-account Remove + "Add account".

**Regression caught + fixed.** `runReported()` — the path the live app uses — had been rewritten (by the concurrent knowledge-system work) to merge learned recipes but silently **dropped `travel` and `payments`** from the snapshot; only the unused `run()` path still carried them. So flights and refunds/failed-payments never reached the UI. Restored both lists and added a regression test asserting travel/payments/returns all survive `runReported`.

**Status.** 278 tests pass, `flutter analyze` clean. Release build signed (team `68FA4847UT`) and installed to *Suresh Victor's iPhone* (`com.nomail.nomail`) over the wireless connection.

**Needs a live device check (google_sign_in 7.x limitation).** The N-distinct-accounts flow can't be proven without it: sign in as account A, then Settings → Accounts → Add account and pick a *different* Google account B. If iOS returns A again instead of offering B, that's the OS-level single-active-session behaviour, not a bug — the data layer already dedupes and accepts B the moment the OS hands it back.

Related: [[Roadmap]], [[Architecture]]

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

## 2026-08-01 → 02 — Contextual actions, AI audit, and the trust surface

Three sessions running alongside the IA refactor, all in the core layers.

**Actions.** Every insight now carries the action that resolves it:
`domain/actions.dart` builds ordered `InsightAction`s — tracking links
(email link first, then carrier template, then a universal tracker), pay
links including `upi://` intents, subscription manage pages, meeting join
links — always ending with "Open email", the one action that always exists.
`ui/action_sheet.dart` renders them; a single action launches straight
through. Calendar/meeting extraction (`extractors/events.dart`) and link
scoring (`extractors/links.dart`) landed with it. Handoff doc: [[Actions API]].

**AI audit.** The OpenRouter pass stopped being brief-only. It now sees every
rule-extracted insight next to its source email and returns
`InsightVerdicts {rejected, renamed}` — dropping false positives, fixing
mangled brand names ("Nct" → Flipkart). Applied by the pure `applyVerdicts()`
so a bad response can never corrupt a snapshot silently.

**Three date bugs**, found while chasing "the data is dumb" and each quietly
corrupting every dated insight:
1. The day group in `_monthNameDate` greedily ate the first two digits of the
   year — "1 Aug 2026" parsed as day 20 with the year lost. Fixed with
   `(\d{1,2}(?!\d))`.
2. The roll-to-next-year check compared a midnight candidate against a
   *timestamped* anchor, so anything meaning "today" jumped a full year (a
   demo meeting showed 2027).
3. Whitespace after the month name was mandatory, so "due 1 Aug" — how real
   bills write it — never parsed at all.

Plus the reported **"GitHub in delivery"** bug: dev-tool senders say
"shipped", "package" and "delivery" constantly (a diff touching
`package.json` read as a parcel), so `_nonCommerceSenders` drops them.

**Settings became the trust surface** — the app reads a whole mailbox, spends
the user's money, and rewrites their data, so it has to answer three
questions. *What is the AI doing?* (`ai_screen`: masked key, model picker,
a real connection test, live OpenRouter spend and a warning when the key has
no cap). *What is it reading?* (`scan_screen`: emails-per-search, history
depth, per-domain switches, live estimate). *What did it change?*
(`processing_screen`: the pipeline live, plus a plain-language log of every
correction). Full reasoning in [[Settings Plan]].

Also shipped here: `notification_service` (8am brief with Pay/Track/Join
actions), `backfill_stats` (the first-scan "hiding in your inbox" card),
~75 Indian sender templates, and the 365-day receipts window so annual
renewals surface.

## 2026-08-02 — The app learns new content types by itself (`049b453`)

Hardcoding a recipe per merchant does not scale — there is always one more
courier. The user's steer, mid-batch, was the right one: build the mechanism
instead of the list.

NoMail now keeps a **playbook it writes for itself**. Each sync: rules →
playbook over the leftovers → the model as a *teacher* on what nothing
recognised. The model returns a recipe (how to spot the sender, which fields
to pull, which URLs to build) and from the next sync that shape is handled by
rule alone. A learned Delhivery recipe builds the tracking URL with the real
AWB in it, forever, having cost one request once.

Built as `domain/knowledge.dart` (matcher/field/action/ContentType/Playbook
+ `validate()`), `domain/knowledge_mapper.dart` (learned match → typed
insight, degrading to an attention card but **never losing the link**),
`data/ai/knowledge_learner.dart` (sender clustering + ~14 safety rejections),
`data/store/knowledge_store.dart`, and `ui/screens/knowledge_screen.dart`.

The safety work is the substance: a model authoring matchers that run against
someone's mailbox is genuinely risky, so an unanchored matcher can never
match, regexes are probed against a dense string to reject catch-alls,
declared domains must appear in the cluster the recipe came from, and
templates are scheme-whitelisted. Invalid entries are skipped with a reason
rather than stored. See [[Architecture]] for the contract.

## 2026-08-02 — Sync survives a real mailbox; the spinner explains itself

**Reported:** `Sync failed: ClientException: Bad file descriptor` on a
`maxResults=50` scan. Diagnosis: a scan is one list request per query plus one
per message — up to ~255 sequential requests on a single keep-alive
connection, and phones lose sockets. The bug was not that a socket died; it
was that nothing recovered.

Fixed in three places. `_BearerClient` retries socket errors on a fresh
connection with backoff (rebuilding the request — a `BaseRequest` can only be
sent once, so retrying the original silently fails). `GmailSource` guards each
query and each message individually, counting `failures`, so one dead message
no longer discards the two hundred that already succeeded. And a latent bug
found on the way: the client held a *snapshot* access token, which expires
hourly — it now holds a provider and re-fetches on 401. Total failure still
throws, deliberately: an unreachable Gmail must not render as an empty inbox.

**Then made the wait legible.** The top-right spinner is where people look
when they wonder whether the app has hung, so it is now tappable (→ the live
Processing pipeline), and a card at the top of Today shows the current line
without needing the tap: "Searching packages (3 of 5)", "Reading packages ·
15 of 50", "Checking 19 results with AI", "Studying 6 unrecognised emails".
Multi-account runs append "(account 2)" so the counter restarting makes sense.

281 tests green, on device.

## 2026-08-02 — Links open the app you actually have (`95089fd` → `ca588c9`)

The user noticed the deep-link work had never shipped: `deep_links.dart` did
not exist, `Info.plist` had no `LSApplicationQueriesSchemes`, nothing called
`canLaunchUrl`. Universal links *were* reaching apps, but only because iOS
does that for free — nothing deliberate. Built it properly, in four commits.

**Detection (`95089fd`).** A 44-app catalog (`domain/app_targets.dart`) with
probe schemes, plus `core/installed_apps.dart` sweeping them once per session.
The design point: iOS gives no way to ask whether an app claims an https URL,
so detection uses custom schemes while the launch stays the universal link.
Research bore that out — of 44 apps only **5** publish a documented launch
format (Uber, Ola, Google Maps, Zoom, Google Pay); no Indian courier or
merchant does. A guessed `delhivery://` would have failed silently.

Same commit: the in-app WebView (`webview_flutter`, not
`LaunchMode.inAppBrowserView` — SFSafariViewController gives no callbacks, so
no feedback), and `domain/link_feedback.dart`, where a thumbs-down marks the
learned recipe that produced the URL as suspect. That is the first real
signal on whether a template the AI wrote is actually correct.

The trap that shaped it: a WKWebView carries none of Safari's cookies, so an
auth-gated page renders logged-out and looks exactly like a wrong page. Left
alone, users would have voted down correct links. Known auth hosts skip the
WebView entirely; unknown ones are caught on arrival and recorded as
`loginWall`, deliberately excluded from `isFailure`. A test pins that two
login walls leave a recipe unsuspected while a login wall plus two genuine
wrong-page votes still flags it — the exclusion must not become a hiding
place.

**"Every click goes to the browser" (`b72736a`).** Reported, and true: a
trace over every action the pipeline produces showed **23 of 24** going
external. The cause was not the WebView — it was that **Gmail was not in the
catalog at all**. The most common action in the app is "Open email" →
`mail.google.com`, undetectable, unlabelled, so every one of them looked like
a trip to Safari. Adding `googlegmail://` and `googlecalendar://` (45 schemes,
still under the cap) moved 17 of 24 to the native app. Also dropped `manage`
from the blanket kind-block — the big billing pages were already covered by
the host list, and blocking the kind sent unknown services to Safari too.

**Telling the user (`d79bc67`).** Only the app case had been signposted, so a
row gave no clue whether it would stay or leave. Every row now ends with the
same marker: brand mark + name, a globe for "in NoMail", an out-arrow for
"leaves". Extracted as a pure `destinationHint()` so a test can assert the
three outcomes render three *distinct* icons.

**Teaching it per-host (`ca588c9`, concurrent session).** The remaining gap
is structural: a WKWebView never fires universal links, so an unknown
merchant rendered in-app is *guaranteed* to bypass their app, and the probe
registry can never grow past 50 schemes. `core/host_routing.dart` makes it
learnable instead — one "open outside" tap remembers the host.

367 tests, analyzer clean, on iPhone and iPad.

