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

## Next

**Ship-blocking**
- [ ] Move API keys behind a server-side proxy — `.env` currently ships inside
      the IPA as a Flutter asset
- [ ] Google CASA Tier 2 assessment for the restricted Gmail scope (annual;
      start early, it gates public release)
- [ ] Rotate the OpenRouter key and set a monthly spend cap

**Product**
- [ ] Show the destination app on each action ("Opens in Delhivery") with its
      icon, and detect what is installed — needs `LSApplicationQueriesSchemes`
      in `Info.plist`
- [ ] Per-insight feedback ("this isn't a bill") feeding a local ignore list —
      turns corrections into training data with no server
- [ ] Pre-scan cost estimate ("~200 emails, about ₹2")
- [ ] Home-screen widget + Live Activity for out-for-delivery parcels
      (ranked highest-ROI iOS surfaces in [[One App Vision]])

**Quality**
- [ ] On-device VoiceOver audit of Timeline chip drag-reorder
- [ ] Pin the Timeline chip row (needs a sliver refactor)

Related: [[Requirements]], [[Architecture]], [[Development Log]]
