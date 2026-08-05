# Roadmap

Where the product actually is, and what comes next. The long-range product
plan (life domains, iOS surfaces, monetisation) lives in [[One App Vision]];
this is the build order.

## Done

**Foundation** (2026-08-01) — honest boot, `.env` tolerant load, real Google
Sign-In (google_sign_in 7.x) with an explicit demo mode, rename HMail → NoMail.

**Insight core** — rule extractors for subscriptions, bills, deliveries,
meetings, travel, payment alerts, reads and returns/warranty; a deterministic
daily brief that exists with or without AI; versioned local snapshot store.

**Actions** — every insight carries the link that resolves it: tracking pages,
`upi://` pay intents, manage-subscription pages, meeting join links, always
with "Open email" as the floor. See [[Actions API]].

**Presentation** — generic `Insight` + `rankInsights()` + one `InsightCard`,
so a new insight type is a model, an extractor and one mapper block with zero
navigation code. Four tabs: Today · Money · Timeline · Settings, with a
chip-filtered, drag-reorderable Timeline.

**AI layer** — audit pass that drops misread insights and fixes mangled brand
names, plus the brief. Optional and never fatal.

**Learned knowledge** — the playbook the app writes for itself, applied
deterministically thereafter. See [[Architecture]].

**Settings as the trust surface** — AI connection + spend, scan scope,
processing/audit log, learned-knowledge management. See [[Settings Plan]].

**Reliability** — multi-account Gmail, a client that survives a
several-hundred-request scan, partial-failure tolerance, live progress
reporting, notifications, Drive/iCloud backup.

**Link routing** — installed-app detection across 44 apps, the in-app WebView
with its feedback loop, per-host "open outside" memory, and a destination
marker on every action row. See [[Architecture]].

**Money intelligence** (2026-08-05) — price-hike detection with four guards
against false hikes, the drift line on the Money hero, proactive renewal/bill/
return alerts, and Gmail pagination + quota backoff. Phase B of the pay-worthy
arc, less the two items still open below.

**Trust loops** (2026-08-05) — per-insight corrections ("Not a package") with a
local ignore list that survives rescans and restores; suspect learned recipes
surfaced in Knowledge → Needs review; a pre-scan cost estimate priced from
OpenRouter's live catalog.

## Next

**Ship-blocking**
- [ ] Move API keys behind a server-side proxy — `.env` currently ships inside
      the IPA as a Flutter asset
- [ ] Google CASA Tier 2 assessment for the restricted Gmail scope (annual;
      start early, it gates public release)
- [ ] Rotate the OpenRouter key and set a monthly spend cap — **needs the
      account owner**; the key pasted in chat on 2026-08-01 has no cap
      (`limit: null`) and should be treated as compromised

**Product**
- [ ] Unused-subscription heuristic — paying but no usage signals in mail
- [ ] Annual spend report (shareable)
- [ ] Home-screen widget + Live Activity for out-for-delivery parcels
      (ranked highest-ROI iOS surfaces in [[One App Vision]])

**Quality**
- [ ] On-device VoiceOver audit of Timeline chip drag-reorder
- [ ] Pin the Timeline chip row (needs a sliver refactor)
- [ ] Real-inbox tuning rounds — the last untested claim in the product. Every
      extractor guard so far was written against fixtures and reasoning; only a
      real mailbox says which ones are wrong

## Pay-worthy arc (added 2026-08-04)

Willingness to pay = recurring pain solved + money visibly saved + trust.
Closest paid analog: Rocket Money ($4–12/mo, subscription tracking via bank
linking). NoMail is that from email alone — no bank credentials, all
on-device, zero server cost per user (~100% margin, real privacy story).

**Phase A — Truth (1–2 weeks, blocks everything).** First real-inbox sync +
2–3 extractor tuning rounds from real misses. Fixtures prove nothing to a
paying user. Real-inbox hardening — pagination past 25/query and quota backoff —
**done 2026-08-05** (`8396410`); the tuning rounds are still outstanding and are
now the oldest unmet dependency in the plan.

**Phase B — the pay trigger: Money intelligence.**
- [x] Price-hike detection — done 2026-08-05 (`2a63e61`). Runs pre-merge, since
      merge collapses subscriptions by service and destroys the old amount.
- [ ] Unused-subscription heuristic — paying but no usage signals in mail
- [x] Money-drift counter — done 2026-08-05. Shipped as "±₹X/mo vs before · N
      price changes caught" rather than "found savings": the app can prove a
      price moved, not that the user cancelled anything, and inventing the
      stronger claim would cost the trust the number depends on.
- [ ] Annual spend report (shareable)
- [x] Proactive notifications — done 2026-08-05 (`d2d1a8a`, wired `2a63e61`):
      renewal T-2d, bill T-1d, return window T-1d.

**Phase C — Packaging.**
- [ ] Free/Pro split: free = 1 account + basic insights; Pro = multi-account,
      AI brief + audit, cloud backup, price-hike alerts, full history
- [ ] StoreKit 2 IAP (needs paid Apple team). Anchor ₹499–999/yr India,
      $19.99–29.99/yr US
- [ ] First-60-seconds onboarding: money-shot card already exists — make the
      first scan's "found ₹X hiding in your inbox" the conversion moment

**Phase D — Distribution.**
- [ ] TestFlight beta once paid team active. OAuth test-user cap (100) also
      delays the CASA gate — beta under it
- [ ] CASA Tier 2 + key-proxy server (both already ship-blocking above)
      before public App Store release
- [ ] Privacy nutrition labels, policy page

Defensible core: per-user learned playbook (recipes backup preserves — the
switching cost), and no-server architecture (price floor competitors with
infra can't match).

**Known limits**
- Personal Apple team: builds expire ~7 days and iCloud backup needs a paid
  membership (see `a3a6cdf`)
- Detection is capped at 50 URL schemes by iOS; 45 used. Beyond that, growth
  comes from per-host memory rather than the registry

Related: [[Requirements]], [[Architecture]], [[Development Log]]
